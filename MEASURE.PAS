Unit Measure;
{-----------------------------
Arithmetic for timings and the text that shows them: speeds, elapsed
times, milliseconds, RPM, log lines

Times come from Timer as a BIOS tick count plus the PIT's count within the
tick; TimeDiffUs turns two of those into microseconds. Everything is in
integers: an 8088 has no FPU, and this keeps the program free of the
floating point library.

No BIOS or screen here, so this is unit tested on any OS.
------------------------------}

{ --------- interface -------- }
interface

const
  TicksPerDay = 1573040;  { The BIOS tick count goes back to 0 at midnight }
  CountsPerTick = 65536;  { PIT counts per BIOS tick }

{ Microseconds from (ticks1, counts1) to (ticks2, counts2) }
function TimeDiffUs(ticks1, counts1, ticks2, counts2:longint):longint;
function SpeedText(bytes, ms:longint):string;
function ElapsedText(ms:longint):string;
function MsText(us:longint):string;
function RpmText(periodUs:longint):string;
function MedianOf3(a, b, c:longint):longint;
{ The median of the first n values; sorts them }
function Median(var values:array of longint; n:integer):longint;
function LogLine(hour, minute, second, hundredths:word; text:string):string;
function IntText(value:longint):string;
function Pad2(value:longint):string;
function PadLeft(s:string; width:byte):string;
function PadRight(s:string; width:byte):string;

{ --------- implementation --------- }
implementation

function IntText(value:longint):string;
var
  s:string;
begin
  Str(value, s);
  IntText := s;
end;

function Pad2(value:longint):string;
var
  s:string;
begin
  s := IntText(value);
  if ( length(s) < 2 ) then s := '0' + s;
  Pad2 := s;
end;

function PadLeft(s:string; width:byte):string;
begin
  while ( length(s) < width ) do s := ' ' + s;
  PadLeft := s;
end;

function PadRight(s:string; width:byte):string;
begin
  while ( length(s) < width ) do s := s + ' ';
  PadRight := s;
end;

{ Tenths as "12.3" }
function TenthsText(tenths:longint):string;
begin
  TenthsText := IntText(tenths div 10) + '.' + IntText(tenths mod 10);
end;

function TimeDiffUs(ticks1, counts1, ticks2, counts2:longint):longint;
var
  ticks:longint;
begin
  ticks := ticks2 - ticks1;
  if ( ticks < 0 ) then inc(ticks, TicksPerDay);
  { A tick is 54,925.4 us; a count 0.8381 us }
  TimeDiffUs := ticks * 54925 + ( ( counts2 - counts1 ) * 8381 ) div 10000;
end;

function SpeedText(bytes, ms:longint):string;
begin
  if ( ms <= 0 ) then
    SpeedText := '- KB/s'
  else
    SpeedText := TenthsText(( bytes * 10 div 1024 ) * 1000 div ms) + ' KB/s';
end;

function ElapsedText(ms:longint):string;
var
  seconds:longint;
begin
  seconds := ms div 1000;
  ElapsedText := IntText(seconds div 60) + ':' + Pad2(seconds mod 60) + '.' + IntText(( ms mod 1000 ) div 100);
end;

function MsText(us:longint):string;
begin
  MsText := TenthsText(( us + 50 ) div 100) + ' ms';
end;

function RpmText(periodUs:longint):string;
begin
  if ( periodUs <= 0 ) then
    RpmText := '-'
  else
    RpmText := TenthsText(( 600000000 + periodUs div 2 ) div periodUs);
end;

function MedianOf3(a, b, c:longint):longint;
begin
  if ( a > b ) then begin
    if ( b > c ) then MedianOf3 := b
    else if ( a > c ) then MedianOf3 := c
    else MedianOf3 := a;
  end
  else begin
    if ( a > c ) then MedianOf3 := a
    else if ( b > c ) then MedianOf3 := c
    else MedianOf3 := b;
  end;
end;

function Median(var values:array of longint; n:integer):longint;
var
  i, j:integer;
  t:longint;
begin
  if ( n <= 0 ) then begin
    Median := 0;
    exit;
  end;
  { Insertion sort: a handful of values }
  for i := 1 to n - 1 do begin
    t := values[i];
    j := i - 1;
    while ( j >= 0 ) and ( values[j] > t ) do begin
      values[j + 1] := values[j];
      dec(j);
    end;
    values[j + 1] := t;
  end;
  Median := values[n div 2];
end;

function LogLine(hour, minute, second, hundredths:word; text:string):string;
begin
  LogLine := Pad2(hour) + ':' + Pad2(minute) + ':' + Pad2(second) + '.' + Pad2(hundredths) + ' ' + text;
end;

end.
