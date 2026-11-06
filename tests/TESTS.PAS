Program Tests;
{-----------------------------
FDDBench unit tests: the units with no screen or BIOS, so they run on the
Mac, in CI, or in DOS:

  fpc -Mtp -Fu. -FUbuild -obuild/tests tests/TESTS.PAS && build/tests
------------------------------}
uses
    DiskMap,
    Scenario,
    Measure;

var
  Passes, Failures:integer;

procedure Check(name:string; ok:boolean);
begin
  if ( ok ) then inc(Passes)
  else begin
    inc(Failures);
    writeln('FAIL: ', name);
  end;
end;

function IntText(i:longint):string;
var
  s:string;
begin
  Str(i, s);
  IntText := s;
end;

procedure CheckInt(name:string; expected, actual:longint);
begin
  if ( expected <> actual ) then
    writeln('  ', name, ': expected ', expected, ', got ', actual);
  Check(name, expected = actual);
end;

procedure CheckStr(name:string; expected, actual:string);
begin
  if ( expected <> actual ) then
    writeln('  ', name, ': expected "', expected, '", got "', actual, '"');
  Check(name, expected = actual);
end;

{ ////////////////// DiskMap ////////////////// }

procedure TestLayouts;
begin
  { 1.44 MB: 6 cells a track, 5 cylinders a row, 16 rows }
  Check('1.44 lays out', SetGeometry(80, 2, 18));
  CheckInt('1.44 sectors a cell', 3, SectorsPerCell);
  CheckInt('1.44 cells a track', 6, CellsPerTrack);
  CheckInt('1.44 cylinders a row', 5, CylindersPerRow);
  CheckInt('1.44 rows', 16, RowsUsed);
  CheckInt('1.44 cells', 960, CellCount);
  CheckInt('1.44 width', 68, UsedWidth);

  { 720 KB: 3 cells a track, 10 a row, 8 rows }
  Check('720 lays out', SetGeometry(80, 2, 9));
  CheckInt('720 cylinders a row', 10, CylindersPerRow);
  CheckInt('720 rows', 8, RowsUsed);

  { 360 KB: 40 cylinders, 4 rows }
  Check('360 lays out', SetGeometry(40, 2, 9));
  CheckInt('360 rows', 4, RowsUsed);

  { 1.2 MB: 15 sectors, 5 cells a track }
  Check('1.2 lays out', SetGeometry(80, 2, 15));
  CheckInt('1.2 cells a track', 5, CellsPerTrack);
  CheckInt('1.2 rows', 14, RowsUsed);

  { 1.68 MB DMF (21 sectors): 3 a cell needs 20 rows, so 6 a cell }
  Check('DMF lays out', SetGeometry(80, 2, 21));
  CheckInt('DMF sectors a cell', 6, SectorsPerCell);
  Check('DMF fits', RowsUsed <= MapRows);

  { 2.88 MB (36 sectors) }
  Check('2.88 lays out', SetGeometry(80, 2, 36));
  Check('2.88 fits', RowsUsed <= MapRows);

  Check('no cylinders', not SetGeometry(0, 2, 18));
  Check('three heads', not SetGeometry(80, 3, 18));
end;

procedure TestPositions;
var
  cell, fromCell, toCell:integer;
  row:byte;
  widest:integer;
begin
  SetGeometry(80, 2, 18);
  cell := CellOf(0, 0, 1);
  CheckInt('first cell', 0, cell);
  CheckInt('first column', LabelWidth, CellColumn(cell));
  CheckInt('first row', 0, CellRow(cell));

  { Head 1 follows head 0 in the same cylinder group }
  CheckInt('head 1 column', LabelWidth + 6, CellColumn(CellOf(0, 1, 1)));
  { Sectors 4-6 are the second cell }
  CheckInt('sector 4', 1, CellOf(0, 0, 4));
  CheckInt('sector 18', 5, CellOf(0, 0, 18));
  { Cylinder 1 starts after a space }
  CheckInt('cylinder 1 column', LabelWidth + 13, CellColumn(CellOf(1, 0, 1)));
  { Cylinder 5 starts row 1 }
  CheckInt('cylinder 5 row', 1, CellRow(CellOf(5, 0, 1)));
  CheckInt('cylinder 5 column', LabelWidth, CellColumn(CellOf(5, 0, 1)));
  CheckInt('last cell', CellCount - 1, CellOf(79, 1, 18));
  CheckInt('last row', 15, CellRow(CellOf(79, 1, 18)));
  CheckStr('row label', 'C05', RowLabel(1));
  CheckStr('last row label', 'C75', RowLabel(15));

  CellRange(3, 1, 7, 6, fromCell, toCell);
  CheckInt('range from', CellOf(3, 1, 7), fromCell);
  CheckInt('range to', CellOf(3, 1, 12), toCell);

  { Every layout stays inside the map }
  for row := 0 to 5 do begin
    case row of
      0: SetGeometry(80, 2, 18);
      1: SetGeometry(80, 2, 9);
      2: SetGeometry(40, 2, 9);
      3: SetGeometry(80, 2, 15);
      4: SetGeometry(80, 2, 21);
      5: SetGeometry(84, 2, 36);
    end;
    widest := CellColumn(CellOf(CylindersPerRow - 1, Geometry.Heads - 1, Geometry.Sectors));
    Check('layout ' + IntText(row) + ' fits across', widest < MapWidth);
    Check('layout ' + IntText(row) + ' width', ( UsedWidth = widest + 1 ) and ( UsedWidth <= MapWidth ));
  end;
end;

procedure TestMarking;
begin
  SetGeometry(80, 2, 18);
  MarkSectors(0, 0, 1, 18, csRead);
  Check('track read', ( Cells[0] = csRead ) and ( Cells[5] = csRead ));
  Check('next track untouched', Cells[6] = csNotYet);
  MarkSectors(0, 0, 4, 1, csError);
  Check('error', Cells[1] = csError);
  MarkSectors(0, 0, 1, 18, csWritten);
  Check('error stays', Cells[1] = csError);
  Check('written', Cells[0] = csWritten);
  MarkSectors(0, 0, 1, 18, csNotYet);
  Check('cleared', Cells[1] = csNotYet);
end;

{ ////////////////// Scenario ////////////////// }

function CountSteps(kind:TScenarioKind; var reads, sectors:longint; var allValid:boolean):integer;
var
  run:TScenarioRun;
  step:TStep;
  n:integer;
begin
  StartScenario(run, kind);
  n := 0;
  reads := 0;
  sectors := 0;
  allValid := true;
  while NextStep(run, step) do begin
    inc(n);
    if ( step.Kind = skRead ) then begin
      inc(reads);
      inc(sectors, step.Count);
      if ( step.Cylinder >= Geometry.Cylinders ) or ( step.Head >= Geometry.Heads )
         or ( step.Sector < 1 ) or ( step.Count < 1 )
         or ( step.Sector + step.Count - 1 > Geometry.Sectors ) then allValid := false;
    end;
    if ( n > 10000 ) then break;
  end;
  CountSteps := n;
end;

procedure TestScenarios;
var
  kind:TScenarioKind;
  reads, sectors:longint;
  valid:boolean;
  geometry:integer;
begin
  for geometry := 0 to 2 do begin
    case geometry of
      0: SetGeometry(80, 2, 18);
      1: SetGeometry(80, 2, 9);
      2: SetGeometry(40, 1, 8);
    end;
    for kind := FirstScenario to LastScenario do begin
      CountSteps(kind, reads, sectors, valid);
      Check(ScenarioName(kind) + ' reads only real sectors (' + IntText(geometry) + ')', valid);
      Check(ScenarioName(kind) + ' reads something (' + IntText(geometry) + ')', reads > 0);
    end;
  end;

  SetGeometry(80, 2, 18);
  CountSteps(scSequential, reads, sectors, valid);
  CheckInt('sequential reads every track', 160, reads);
  CheckInt('sequential reads every sector', 2880, sectors);
  CountSteps(scRandom, reads, sectors, valid);
  CheckInt('random reads', RandomReads, reads);
  CountSteps(scButterfly, reads, sectors, valid);
  CheckInt('butterfly visits every cylinder', 80, reads);
end;

procedure TestRepeatable;
var
  a, b:TScenarioRun;
  sa, sb:TStep;
  same:boolean;
begin
  SetGeometry(80, 2, 18);
  StartScenario(a, scRandom);
  StartScenario(b, scRandom);
  same := true;
  while NextStep(a, sa) do begin
    NextStep(b, sb);
    if ( sa.Cylinder <> sb.Cylinder ) or ( sa.Head <> sb.Head ) or ( sa.Sector <> sb.Sector ) then same := false;
  end;
  Check('random is the same every run', same);
end;

procedure TestButterflyOrder;
var
  run:TScenarioRun;
  step:TStep;
begin
  SetGeometry(80, 2, 18);
  StartScenario(run, scButterfly);
  NextStep(run, step); CheckInt('butterfly 1', 0, step.Cylinder);
  NextStep(run, step); CheckInt('butterfly 2', 79, step.Cylinder);
  NextStep(run, step); CheckInt('butterfly 3', 1, step.Cylinder);
  NextStep(run, step); CheckInt('butterfly 4', 78, step.Cylinder);
end;

procedure TestLogical;
var
  c, h, s:byte;
begin
  SetGeometry(80, 2, 18);
  LogicalToCHS(0, c, h, s);
  Check('logical 0', ( c = 0 ) and ( h = 0 ) and ( s = 1 ));
  LogicalToCHS(18, c, h, s);
  Check('logical 18', ( c = 0 ) and ( h = 1 ) and ( s = 1 ));
  LogicalToCHS(2879, c, h, s);
  Check('logical last', ( c = 79 ) and ( h = 1 ) and ( s = 18 ));
end;

{ ////////////////// Measure ////////////////// }

procedure TestMeasure;
begin
  CheckStr('speed', '17.0 KB/s', SpeedText(17408, 1000));
  CheckStr('speed no time', '- KB/s', SpeedText(1000, 0));
  CheckStr('speed whole disk', '45.0 KB/s', SpeedText(1474560, 32000));
  CheckStr('elapsed', '0:23.4', ElapsedText(23456));
  CheckStr('elapsed minutes', '12:05.0', ElapsedText(725000));
  CheckStr('ms', '3.2 ms', MsText(3210));
  CheckStr('ms big', '200.0 ms', MsText(200000));
  CheckStr('rpm', '300.0', RpmText(200000));
  CheckStr('rpm 360', '360.0', RpmText(166667));
  CheckStr('revs', '1.05 rev', RevsText(210000, 200000));
  CheckStr('revs small', '0.11 rev', RevsText(22222, 200000));
  CheckStr('revs no period', '-', RevsText(1000, 0));
  CheckInt('ticks to us', 54925, TimeDiffUs(10, 0, 11, 0));
  CheckInt('counts to us', 838, TimeDiffUs(10, 0, 10, 1000));
  CheckInt('midnight', 54925, TimeDiffUs(1573039, 0, 0, 0));
  CheckInt('median odd', 5, MedianOf3(9, 5, 1));
  CheckStr('log line', '09:05:03.07 Sequential read: start', LogLine(9, 5, 3, 7, 'Sequential read: start'));
end;

begin
  Passes := 0;
  Failures := 0;
  TestLayouts;
  TestPositions;
  TestMarking;
  TestScenarios;
  TestRepeatable;
  TestButterflyOrder;
  TestLogical;
  TestMeasure;
  writeln(Passes, ' passed, ', Failures, ' failed');
  if ( Failures > 0 ) then Halt(1);
end.
