Unit Timer;
{-----------------------------
Microsecond timing from the PC's 8253/8254 timer

The BIOS counts ticks (18.2 a second) at 0040:006C, too coarse for a 3 ms
step. Within each tick, the PIT's channel 0 counts down from 65536 at
1.193 MHz, so latching it gives a count to 0.84 us. The BIOS runs channel 0
in mode 3 (square wave), where the count goes down by two, twice a tick,
which can't be read back as a time; StartTimer switches it to mode 2 (rate
generator) with the same divisor, so the tick rate is unchanged and the
count goes down by one, once a tick. StopTimer puts mode 3 back: call it
before exiting (FDDBench does, in its exit procedure).

The ticks are FDDBench's own, counted by its INT 08h handler (which then
chains to the BIOS's), not the BIOS's count at 0040:006C: some BIOSes keep
that count in step with the CMOS clock, which hides a timer that runs fast.
The Evesham's ran 1.55% fast against FDDSynthPro's crystal over 33-433 ms,
while its BIOS count agreed with it to 0.16% over minutes. StartTimer
installs the handler and StopTimer removes it.
------------------------------}

{ --------- interface -------- }
interface

type
  TTime = record
    Ticks:longint;      { Timer ticks counted by FDDBench since StartTimer }
    Counts:longint;     { PIT counts into the tick, 0-65535 }
    BiosTicks:longint;  { The BIOS's count at the same moment (0040:006C) }
  end;

procedure StartTimer;
procedure StopTimer;
procedure GetTime(var t:TTime);
function SinceUs(var t:TTime):longint;
function SinceMs(var t:TTime):longint;
{ The CMOS clock's seconds register (an AT's real-time clock, on its own
  32 kHz crystal); 255 when an update is in progress. An XT has no CMOS
  clock: the port reads back the same value for ever }
function CmosSeconds:byte;
{ Microseconds across `seconds` whole CMOS seconds (from one second ticking
  over to another): by the PIT (`pitUs`) and by the BIOS's tick count with
  the PIT's counts within the tick (`biosUs`). False if the CMOS clock
  doesn't tick }
function TimeCmosSeconds(seconds:byte; var pitUs, biosUs:longint):boolean;

{ --------- implementation --------- }
implementation
uses
    Dos,
    Measure;

var
  running:boolean;
  ownTicks:longint;  { Counted by TickHandler }
  oldInt8:pointer;   { The BIOS's handler }

{ IRQ0: count the tick, then on to the BIOS's handler (its clock, the
  floppy motor's timeout, INT 1Ch and the end of interrupt), as an INT would
  call it }
procedure TickHandler; interrupt;
begin
  inc(ownTicks);
  asm
    pushf
    call dword ptr [oldInt8]
  end;
end;

procedure StartTimer;
begin
  if running then exit;
  ownTicks := 0;
  GetIntVec($08, oldInt8);
  asm cli end;
  port[$43] := $34;  { Channel 0, low then high byte, mode 2, binary }
  port[$40] := 0;    { Divisor 65536, as the BIOS sets it }
  port[$40] := 0;
  SetIntVec($08, @TickHandler);
  asm sti end;
  running := true;
end;

procedure StopTimer;
begin
  if not running then exit;
  asm cli end;
  SetIntVec($08, oldInt8);
  port[$43] := $36;  { Mode 3, as the BIOS left it }
  port[$40] := 0;
  port[$40] := 0;
  asm sti end;
  running := false;
end;

procedure GetTime(var t:TTime);
var
  lo, hi, irr:byte;
  ticks, bios:longint;
  count:word;
  counts:longint;
begin
  asm cli end;
  port[$43] := $00;  { Latch channel 0's count }
  lo := port[$40];
  hi := port[$40];
  ticks := ownTicks;
  bios := meml[$40:$6C];
  port[$20] := $0A;  { Read the PIC's request register }
  irr := port[$20];
  asm sti end;

  count := word(hi) shl 8 or lo;
  counts := ( 65536 - longint(count) ) and $FFFF;
  { The count wrapped but the tick's interrupt hasn't run yet: it's due }
  if ( irr and 1 <> 0 ) and ( counts < 32768 ) then begin
    inc(ticks);
    inc(bios);
  end;
  if ( bios >= TicksPerDay ) then dec(bios, TicksPerDay);
  t.Ticks := ticks;
  t.Counts := counts;
  t.BiosTicks := bios;
end;

function SinceUs(var t:TTime):longint;
var
  now:TTime;
begin
  GetTime(now);
  SinceUs := TimeDiffUs(t.Ticks, t.Counts, now.Ticks, now.Counts);
end;

function SinceMs(var t:TTime):longint;
begin
  SinceMs := SinceUs(t) div 1000;
end;

function CmosSeconds:byte;
var
  s:byte;
begin
  asm cli end;
  port[$70] := $0A;
  if ( port[$71] and $80 ) <> 0 then s := 255  { Updating }
  else begin
    port[$70] := $00;
    s := port[$71];
  end;
  asm sti end;
  CmosSeconds := s;
end;

{ Waits for the seconds register to read a value other than `second` (and
  not mid-update), then sets `second` to it; false after 2.5 s, so a PC
  with no CMOS clock (an XT: the port reads the same, or "updating", for
  ever) never hangs here }
function WaitTick(var second:byte; var at:TTime):boolean;
var
  start:TTime;
  s:byte;
begin
  GetTime(start);
  repeat
    s := CmosSeconds;
    if ( s <> 255 ) and ( s <> second ) then begin
      GetTime(at);
      second := s;
      WaitTick := true;
      exit;
    end;
  until SinceUs(start) > 2500000;
  WaitTick := false;
end;

function TimeCmosSeconds(seconds:byte; var pitUs, biosUs:longint):boolean;
var
  t0, t1:TTime;
  s:byte;
  i:integer;
begin
  TimeCmosSeconds := false;
  s := CmosSeconds;
  if not WaitTick(s, t0) then exit;  { From the start of a second }
  t1 := t0;
  for i := 1 to seconds do
    if not WaitTick(s, t1) then exit;
  pitUs := TimeDiffUs(t0.Ticks, t0.Counts, t1.Ticks, t1.Counts);
  biosUs := TimeDiffUs(t0.BiosTicks, t0.Counts, t1.BiosTicks, t1.Counts);
  TimeCmosSeconds := true;
end;

begin
  running := false;
  ownTicks := 0;
end.
