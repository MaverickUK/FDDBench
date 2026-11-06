Unit Bench;
{-----------------------------
The benchmark: rotation, sequential read, track-to-track, full stroke and
average access, all timed from one read finishing to the next

A floppy has no "seek complete" signal, so software can only time reads.
Times between completions are what the drive and the PC together give:
  Rotation      the same sector read again and again comes round once a
                revolution, so the gap between reads is the period
  Changing      sector 1 on one cylinder, then sector 1+k on another: the
  cylinders     smallest k that's caught on the same revolution gives the
                time to change cylinders (step, the head settling, the
                emulator loading the track), to one sector's time
  Access        random single sectors
  Sequential    every track, a whole track a read (KB/s, and revolutions a
                track: 1 is perfect, more means a track was missed)
------------------------------}

{ --------- interface -------- }
interface

type
  TBenchResult = record
    PeriodUs:longint;        { One revolution }
    SequentialUs:longint;    { The whole disk }
    SequentialBytes:longint;
    TrackToTrackUs:longint;
    FullStrokeUs:longint;
    AccessUs:longint;        { Average }
    Errors:longint;
    Retries:longint;
    Complete:boolean;        { False if stopped with Esc }
  end;

  TResultLine = record
    Name:string[24];
    Value:string[20];
    Note:string[40];
  end;

const
  ResultLines = 6;
  RotationReads = 21;
  RealPeriodUs = 100000;   { Faster than 600 RPM isn't a floppy drive: revolutions mean nothing }
  AccessReads = 50;

var
  Stopped:boolean;

procedure RunBenchmark(drive:byte; var r:TBenchResult);
procedure GetResultLine(var r:TBenchResult; i:integer; var line:TResultLine);

{ --------- implementation --------- }
implementation
uses
    Crt,
    DiskMap,
    Scenario,
    Measure,
    Timer,
    BiosDisk,
    View;

var
  benchDrive:byte;
  lastDone:TTime;
  errors:longint;
  testName:string;

procedure CheckStop;
var
  c:char;
begin
  while KeyPressed do begin
    c := ReadKey;
    if ( c = #0 ) then ReadKey
    else if ( c = #27 ) then Stopped := true;
  end;
end;

procedure Progress(text:string);
begin
  DrawStatus(0, PadRight(testName, 22) + text);
end;

{ Reads, draws it on the map, and returns the microseconds since the last
  read finished (-1 if it failed) }
function TimedRead(cylinder, head, sector, count:byte):longint;
var
  now:TTime;
  status:byte;
  fromCell, toCell, cell:integer;
begin
  CellRange(cylinder, head, sector, count, fromCell, toCell);
  DrawHead(fromCell, toCell);
  status := ReadSectors(benchDrive, cylinder, head, sector, count);
  GetTime(now);
  if ( status = 0 ) then begin
    TimedRead := TimeDiffUs(lastDone.Ticks, lastDone.Counts, now.Ticks, now.Counts);
    MarkSectors(cylinder, head, sector, count, csRead);
  end
  else begin
    TimedRead := -1;
    inc(errors);
    MarkSectors(cylinder, head, sector, count, csError);
  end;
  lastDone := now;
  for cell := fromCell to toCell do DrawCell(cell);
  CheckStop;
end;

function MeasureRotation:longint;
var
  samples:array[0..RotationReads - 1] of longint;
  n, i:integer;
  us:longint;
begin
  testName := 'Rotation';
  TimedRead(0, 0, 1, 1);  { The head to cylinder 0 }
  n := 0;
  for i := 1 to RotationReads do begin
    if Stopped then break;
    us := TimedRead(0, 0, 1, 1);
    if ( us > 0 ) then begin
      samples[n] := us;
      inc(n);
    end;
    Progress('read ' + IntText(i) + ' of ' + IntText(RotationReads));
  end;
  MeasureRotation := Median(samples, n);
end;

{ The shortest time from reading sector 1 on cylinder a to reading a sector
  on cylinder b, trying each sector in turn }
function ChangeCost(a, b:byte):longint;
var
  k:integer;
  us, best:longint;
begin
  best := -1;
  for k := 0 to Geometry.Sectors - 1 do begin
    if Stopped then break;
    TimedRead(a, 0, 1, 1);
    us := TimedRead(b, 0, 1 + k, 1);
    if ( us > 0 ) and ( ( best < 0 ) or ( us < best ) ) then best := us;
    Progress('cylinder ' + IntText(a) + ' to ' + IntText(b) + ', sector ' + IntText(1 + k));
  end;
  ChangeCost := best;
end;

function MeasureAccess:longint;
var
  run:TScenarioRun;
  step:TStep;
  i, n:integer;
  us, total:longint;
begin
  testName := 'Average access';
  StartScenario(run, scRandom);
  total := 0;
  n := 0;
  TimedRead(0, 0, 1, 1);
  for i := 1 to AccessReads do begin
    if Stopped or not NextStep(run, step) then break;
    us := TimedRead(step.Cylinder, step.Head, step.Sector, 1);
    if ( us > 0 ) then begin
      inc(total, us);
      inc(n);
    end;
    Progress('read ' + IntText(i) + ' of ' + IntText(AccessReads));
  end;
  if ( n > 0 ) then MeasureAccess := total div n else MeasureAccess := -1;
end;

procedure MeasureSequential(var r:TBenchResult);
var
  start:TTime;
  c, h:integer;
begin
  testName := 'Sequential read';
  TimedRead(0, 0, 1, 1);
  GetTime(start);
  r.SequentialBytes := 0;
  for c := 0 to Geometry.Cylinders - 1 do
    for h := 0 to Geometry.Heads - 1 do begin
      if Stopped then exit;
      if ( TimedRead(c, h, 1, Geometry.Sectors) >= 0 ) then
        inc(r.SequentialBytes, longint(Geometry.Sectors) * SectorBytes);
      Progress('cylinder ' + IntText(c) + ' head ' + IntText(h));
    end;
  r.SequentialUs := SinceUs(start);
end;

procedure RunBenchmark(drive:byte; var r:TBenchResult);
var
  retriesBefore:longint;
begin
  benchDrive := drive;
  Stopped := false;
  errors := 0;
  retriesBefore := Retries;
  r.PeriodUs := -1;
  r.SequentialUs := -1;
  r.SequentialBytes := 0;
  r.TrackToTrackUs := -1;
  r.FullStrokeUs := -1;
  r.AccessUs := -1;
  GetTime(lastDone);

  ClearCells;
  DrawMap;
  r.PeriodUs := MeasureRotation;
  if not Stopped then begin
    testName := 'Track-to-track';
    r.TrackToTrackUs := ChangeCost(Geometry.Cylinders div 2, Geometry.Cylinders div 2 + 1);
  end;
  if not Stopped then begin
    testName := 'Full stroke';
    r.FullStrokeUs := ChangeCost(0, Geometry.Cylinders - 1);
  end;
  if not Stopped then r.AccessUs := MeasureAccess;
  if not Stopped then begin
    ClearCells;
    DrawMap;
    MeasureSequential(r);
  end;
  r.Errors := errors;
  r.Retries := Retries - retriesBefore;
  r.Complete := not Stopped;
end;

function UsOrDash(us:longint):string;
begin
  if ( us < 0 ) then UsOrDash := '-' else UsOrDash := MsText(us);
end;

function RevsNote(us, periodUs:longint):string;
begin
  if ( us < 0 ) or ( periodUs <= 0 ) then RevsNote := ''
  else RevsNote := RevsText(us, periodUs);
end;

procedure GetResultLine(var r:TBenchResult; i:integer; var line:TResultLine);
var
  tracks:longint;
begin
  line.Note := '';
  case i of
    0: begin
         line.Name := 'Rotation';
         if ( r.PeriodUs <= 0 ) then line.Value := '-'
         else begin
           line.Value := RpmText(r.PeriodUs) + ' RPM';
           if ( r.PeriodUs < RealPeriodUs ) then
             line.Note := 'too fast for a drive: an emulator?'
           else
             line.Note := MsText(r.PeriodUs) + ' a revolution';
         end;
       end;
    1: begin
         line.Name := 'Sequential read';
         if ( r.SequentialUs <= 0 ) then line.Value := '-'
         else begin
           line.Value := SpeedText(r.SequentialBytes, r.SequentialUs div 1000);
           tracks := r.SequentialBytes div ( longint(Geometry.Sectors) * SectorBytes );
           if ( tracks > 0 ) and ( r.PeriodUs >= RealPeriodUs ) then
             line.Note := RevsText(r.SequentialUs div tracks, r.PeriodUs) + ' a track';
         end;
       end;
    2: begin
         line.Name := 'Track-to-track';
         line.Value := UsOrDash(r.TrackToTrackUs);
         if ( r.PeriodUs >= RealPeriodUs ) then line.Note := RevsNote(r.TrackToTrackUs, r.PeriodUs);
       end;
    3: begin
         line.Name := 'Full stroke';
         line.Value := UsOrDash(r.FullStrokeUs);
         if ( r.PeriodUs >= RealPeriodUs ) then line.Note := RevsNote(r.FullStrokeUs, r.PeriodUs);
       end;
    4: begin
         line.Name := 'Average access';
         line.Value := UsOrDash(r.AccessUs);
         if ( r.PeriodUs >= RealPeriodUs ) then line.Note := RevsNote(r.AccessUs, r.PeriodUs);
       end;
    5: begin
         line.Name := 'Errors / retries';
         line.Value := IntText(r.Errors) + ' / ' + IntText(r.Retries);
         if ( r.Errors > 0 ) then line.Note := 'reads the BIOS gave up on'
         else if ( r.Retries > 0 ) then line.Note := 'reads that needed a retry';
       end;
  end;
end;

end.
