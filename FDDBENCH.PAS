Program FDDBench;
{-----------------------------
FDDBench - floppy drive sounds and benchmark for DOS

  FDDBENCH [A: | B:] [/AUTO] [/DUMP:file]

    A: B:       the drive to test (A: if left out)
    /AUTO       run every scenario, then exit
    /DUMP:file  with /AUTO, save the final screen's text to a file

Startup, the menu and running the scenarios. The scenarios themselves are
in Scenario, the map in DiskMap and View, the BIOS calls in BiosDisk.
------------------------------}
{$IFNDEF FPC}
  {$M 16384,0,655360}
{$ENDIF}
uses
    FpuFix,
    Crt,
    Dos,
    DiskMap,
    Scenario,
    Measure,
    Timer,
    BiosDisk,
    View;

{$I VERSION.INC}

const
  LogName = 'FDDBENCH.LOG';
  MaxLogLines = 100;
  PauseBetweenMs = 1500;
  MenuFooter = '1-9~scenario|  A~run all|  Esc~quit';
  RunFooter = 'Esc~stop|  Space~pause';

var
  Drive:byte;
  DriveLetter:char;
  Auto:boolean;
  DumpFile:string;
  DriveText:string;

  { This scenario's figures }
  HeadCylinder:integer;   { -1 before the first read }
  Steps, Seeks, Errors:longint;
  BytesRead, BytesWritten:longint;
  Started:TTime;
  Stopped:boolean;
  Operation:string;
  Position:string;

  LogLines:array[1..MaxLogLines] of string[100];
  LogCount:integer;
  LogPath:string;
  OldExit:pointer;

{ ////////////////// The log ////////////////// }

procedure FlushLog;
var
  f:text;
  i:integer;
begin
  if ( LogCount = 0 ) then exit;
  Assign(f, LogPath);
  {$I-} Append(f); {$I+}
  if ( IOResult <> 0 ) then begin
    {$I-} Rewrite(f); {$I+}
    if ( IOResult <> 0 ) then begin LogCount := 0; exit; end;
  end;
  for i := 1 to LogCount do writeln(f, LogLines[i]);
  Close(f);
  LogCount := 0;
end;

{ Kept in memory and written between scenarios: writing to the disk under
  test mid-scenario would add its own seeks to the sound }
procedure Log(text:string);
var
  h, m, s, hund:word;
begin
  Dos.GetTime(h, m, s, hund);
  if ( LogCount >= MaxLogLines ) then FlushLog;
  inc(LogCount);
  LogLines[LogCount] := LogLine(h, m, s, hund, text);
end;

{ ////////////////// Status ////////////////// }

{ Rounded up, so a single sector shows as 1 KB rather than 0 }
function KBText(bytes:longint):string;
begin
  KBText := IntText(( bytes + 1023 ) div 1024) + ' KB';
end;

function ElapsedMs:longint;
begin
  ElapsedMs := SinceMs(Started);
end;

procedure ShowStatus;
var
  ms:longint;
begin
  ms := ElapsedMs;
  DrawStatus(0, PadRight(Position, 30) + PadRight(Operation, 14) + 'Elapsed ' + PadRight(ElapsedText(ms), 12)
             + 'Steps ' + IntText(Steps));
  DrawStatus(1, PadRight('Read ' + KBText(BytesRead), 13)
             + PadRight('Written ' + KBText(BytesWritten), 17)
             + PadRight('Errors ' + IntText(Errors), 14)
             + 'Speed   ' + PadRight(SpeedText(BytesRead + BytesWritten, ms), 12) + 'Seeks ' + IntText(Seeks));
end;

procedure ShowLegend;
begin
  DrawStatus(2, #219' read  '#178' written  '#177' head  '#176' not yet  X error');
end;

{ ////////////////// Keys ////////////////// }

{ Esc stops the scenario; Space pauses it until another key }
procedure CheckKeys;
var
  c:char;
begin
  while KeyPressed do begin
    c := ReadKey;
    if ( c = #0 ) then ReadKey
    else if ( c = #27 ) then Stopped := true
    else if ( c = ' ' ) then begin
      DrawFooter('Paused: any key~to go on');
      c := ReadKey;
      if ( c = #0 ) then ReadKey;
      if ( c = #27 ) then Stopped := true;
      DrawFooter(RunFooter);
    end;
  end;
end;

{ ////////////////// Steps ////////////////// }

procedure DoRead(var step:TStep);
var
  fromCell, toCell, cell:integer;
  status:byte;
  last:byte;
begin
  if ( HeadCylinder >= 0 ) and ( HeadCylinder <> step.Cylinder ) then begin
    inc(Steps, abs(HeadCylinder - step.Cylinder));
    inc(Seeks);
  end;
  HeadCylinder := step.Cylinder;

  last := step.Sector + step.Count - 1;
  Position := 'Cyl ' + PadRight(IntText(step.Cylinder), 3) + ' Head ' + IntText(step.Head) + '  Sector ' + IntText(step.Sector);
  if ( step.Count > 1 ) then Position := Position + '-' + IntText(last);
  Operation := 'Reading';
  CellRange(step.Cylinder, step.Head, step.Sector, step.Count, fromCell, toCell);
  DrawHead(fromCell, toCell);
  ShowStatus;

  status := ReadSectors(Drive, step.Cylinder, step.Head, step.Sector, step.Count);
  if ( status = 0 ) then begin
    MarkSectors(step.Cylinder, step.Head, step.Sector, step.Count, csRead);
    inc(BytesRead, longint(step.Count) * SectorBytes);
  end
  else begin
    MarkSectors(step.Cylinder, step.Head, step.Sector, step.Count, csError);
    inc(Errors);
    Log('  read C' + IntText(step.Cylinder) + ' H' + IntText(step.Head) + ' S' + IntText(step.Sector)
        + '+' + IntText(step.Count) + ': ' + StatusText(status));
  end;
  for cell := fromCell to toCell do DrawCell(cell);
end;

procedure DoWait(ms:word);
var
  t:TTime;
  shown:longint;
begin
  Operation := 'Waiting';
  ShowStatus;
  GetTime(t);
  shown := 0;
  while ( SinceMs(t) < ms ) and not Stopped do begin
    CheckKeys;
    if ( SinceMs(t) - shown >= 100 ) then begin
      shown := SinceMs(t);
      ShowStatus;
    end;
  end;
end;

procedure DoReset;
begin
  Operation := 'Resetting';
  ShowStatus;
  ResetDrive(Drive);
  HeadCylinder := 0;  { The BIOS recalibrates: the next read seeks from cylinder 0 }
end;

{ ////////////////// Scenarios ////////////////// }

function RunScenario(kind:TScenarioKind):boolean;
var
  run:TScenarioRun;
  step:TStep;
  ms:longint;
begin
  ClearCells;
  DrawMap;
  DrawHeading(ScenarioName(kind) + ': ' + ScenarioHint(kind));
  DrawFooter(RunFooter);
  ShowLegend;
  Steps := 0;
  Seeks := 0;
  Errors := 0;
  BytesRead := 0;
  BytesWritten := 0;
  Stopped := false;
  Position := '';
  Operation := '';
  GetTime(Started);
  Log(ScenarioName(kind) + ': start');

  StartScenario(run, kind);
  while not Stopped and NextStep(run, step) do begin
    case step.Kind of
      skRead: DoRead(step);
      skWait: DoWait(step.WaitMs);
      skReset: DoReset;
    end;
    CheckKeys;
  end;

  ms := ElapsedMs;
  if ( Stopped ) then Operation := 'Stopped' else Operation := 'Done';
  Position := '';
  ShowStatus;
  Log(ScenarioName(kind) + ': ' + Operation + ' in ' + ElapsedText(ms) + ', read ' + KBText(BytesRead) + ', ' + IntText(Seeks) + ' seeks, ' + IntText(Steps) + ' steps, ' + IntText(Errors) + ' errors, '
      + SpeedText(BytesRead + BytesWritten, ms));
  FlushLog;
  RunScenario := not Stopped;
end;

procedure RunAll;
var
  kind:TScenarioKind;
  t:TTime;
begin
  Log('Run all: start');
  for kind := FirstScenario to LastScenario do begin
    if not RunScenario(kind) then break;
    if ( kind <> LastScenario ) then begin
      GetTime(t);
      while ( SinceMs(t) < PauseBetweenMs ) do ;
    end;
  end;
  Log('Run all: end');
  FlushLog;
end;

{ ////////////////// Menu ////////////////// }

procedure ShowMenu;
var
  kind:TScenarioKind;
  line:string;
  n:integer;
begin
  DrawHeading('Choose a scenario');
  line := '';
  n := 0;
  for kind := FirstScenario to LastScenario do begin
    inc(n);
    line := line + PadRight(IntText(n) + ' ' + ScenarioName(kind), 19);
    if ( n mod 4 = 0 ) then begin
      DrawStatus(n div 4 - 1, line);
      line := '';
    end;
  end;
  DrawStatus(2, line + 'A Run all');
  DrawFooter(MenuFooter);
end;

procedure MenuLoop;
var
  c:char;
  n:integer;
begin
  repeat
    ShowMenu;
    c := UpCase(ReadKey);
    if ( c = #0 ) then begin ReadKey; continue; end;
    if ( c >= '1' ) and ( c <= '9' ) then begin
      n := ord(c) - ord('1');
      if ( n <= ord(LastScenario) ) then RunScenario(TScenarioKind(n));
    end
    else if ( c = 'A' ) then RunAll;
  until c = #27;
end;

{ ////////////////// Startup ////////////////// }

procedure ParseCommandLine;
var
  i, n:integer;
  p:string;
begin
  Drive := 0;
  DriveLetter := 'A';
  Auto := false;
  DumpFile := '';
  for i := 1 to ParamCount do begin
    p := ParamStr(i);
    for n := 1 to length(p) do p[n] := UpCase(p[n]);
    if ( p = 'B:' ) or ( p = 'B' ) then begin Drive := 1; DriveLetter := 'B'; end
    else if ( p = 'A:' ) or ( p = 'A' ) then begin Drive := 0; DriveLetter := 'A'; end
    else if ( p = '/AUTO' ) then Auto := true
    else if ( copy(p, 1, 6) = '/DUMP:' ) then DumpFile := copy(ParamStr(i), 7, 255);
  end;
end;

function FindGeometry:boolean;
var
  cylinders, heads, sectors, kind:byte;
  kindText:string;
begin
  FindGeometry := false;
  kindText := '';
  if DriveGeometry(Drive, cylinders, heads, sectors, kind) then kindText := DriveKindText(kind) + ' drive, ';
  ResetDrive(Drive);
  if not DiskGeometry(Drive, cylinders, heads, sectors) then exit;
  if not SetGeometry(cylinders, heads, sectors) then exit;
  DriveText := DriveLetter + ': ' + kindText
               + IntText(longint(cylinders) * heads * sectors div 2) + 'K disk, '
               + IntText(cylinders) + ' cyl ' + IntText(heads) + ' heads ' + IntText(sectors) + ' sec ';
  FindGeometry := true;
end;

{$F+}
procedure Cleanup;
begin
  ExitProc := OldExit;
  StopTimer;
  FlushLog;
end;
{$F-}

function ProgramDir:string;
var
  p:string;
  i:integer;
begin
  p := ParamStr(0);
  i := length(p);
  while ( i > 0 ) and ( p[i] <> '\' ) and ( p[i] <> ':' ) do dec(i);
  ProgramDir := copy(p, 1, i);
end;

var
  c:char;
begin
  ParseCommandLine;
  LogPath := ProgramDir + LogName;
  LogCount := 0;
  if not InitBuffer then begin
    writeln('FDDBench: not enough memory');
    Halt(1);
  end;

  OldExit := ExitProc;
  ExitProc := @Cleanup;
  StartTimer;
  InitScreen;
  DrawTitle('');
  DrawFrame;

  while not FindGeometry do begin
    DrawHeading('No disk');
    DrawStatus(0, 'No readable disk in ' + DriveLetter + ':. Insert a formatted disk and press a key, Esc to quit.');
    DrawFooter('Any key~to try again|  Esc~quit');
    if ( Auto ) then begin
      DoneScreen;
      writeln('FDDBench: no readable disk in ', DriveLetter, ':');
      Halt(2);
    end;
    c := ReadKey;
    if ( c = #0 ) then ReadKey;
    if ( c = #27 ) then begin
      DoneScreen;
      Halt(0);
    end;
  end;

  Log('FDDBench ' + AppVersion + ': ' + DriveText);
  DrawTitle(DriveText);
  DrawMap;

  if ( Auto ) then begin
    RunAll;
    if ( length(DumpFile) > 0 ) then SaveScreenText(DumpFile);
  end
  else
    MenuLoop;

  DoneScreen;
end.
