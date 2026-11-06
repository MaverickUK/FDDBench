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
------------------------------}

{ --------- interface -------- }
interface

type
  TTime = record
    Ticks:longint;   { BIOS ticks since midnight }
    Counts:longint;  { PIT counts into the tick, 0-65535 }
  end;

procedure StartTimer;
procedure StopTimer;
procedure GetTime(var t:TTime);
function SinceUs(var t:TTime):longint;
function SinceMs(var t:TTime):longint;

{ --------- implementation --------- }
implementation
uses
    Measure;

var
  running:boolean;

procedure StartTimer;
begin
  asm cli end;
  port[$43] := $34;  { Channel 0, low then high byte, mode 2, binary }
  port[$40] := 0;    { Divisor 65536, as the BIOS sets it }
  port[$40] := 0;
  asm sti end;
  running := true;
end;

procedure StopTimer;
begin
  if not running then exit;
  asm cli end;
  port[$43] := $36;  { Mode 3, as the BIOS left it }
  port[$40] := 0;
  port[$40] := 0;
  asm sti end;
  running := false;
end;

procedure GetTime(var t:TTime);
var
  lo, hi, irr:byte;
  ticks:longint;
  count:word;
  counts:longint;
begin
  asm cli end;
  port[$43] := $00;  { Latch channel 0's count }
  lo := port[$40];
  hi := port[$40];
  ticks := meml[$40:$6C];
  port[$20] := $0A;  { Read the PIC's request register }
  irr := port[$20];
  asm sti end;

  count := word(hi) shl 8 or lo;
  counts := ( 65536 - longint(count) ) and $FFFF;
  { The count wrapped but the tick's interrupt hasn't run yet: it's due }
  if ( irr and 1 <> 0 ) and ( counts < 32768 ) then inc(ticks);
  if ( ticks >= TicksPerDay ) then dec(ticks, TicksPerDay);
  t.Ticks := ticks;
  t.Counts := counts;
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

begin
  running := false;
end.
