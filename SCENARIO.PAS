Unit Scenario;
{-----------------------------
The scenarios: each is a series of steps (read some sectors, reset the
controller, wait), worked out from the disk's geometry (DiskMap.Geometry)

A run hands out one step at a time (NextStep), so nothing is held in memory
and the main program can draw and check the keyboard between them. The
"random" ones use their own generator with a fixed seed: a scenario visits
the same sectors every time, so it sounds the same every time.

No BIOS or screen here, so this is unit tested on any OS.
------------------------------}

{ --------- interface -------- }
interface

uses
    DiskMap;

type
  TScenarioKind = (scSpinUp, scRecalibrate, scSingleSteps, scShortSeeks, scFullStroke,
                   scButterfly, scSequential, scRandom, scGameLoad);

  TStepKind = (skRead, skReset, skWait);

  TStep = record
    Kind:TStepKind;
    Cylinder, Head, Sector, Count:byte;  { skRead }
    WaitMs:word;                         { skWait }
  end;

  TScenarioRun = record
    Kind:TScenarioKind;
    Index:integer;      { Steps handed out so far }
    Seed:longint;       { The generator's state }
    { Game loading: the current run of sectors, as logical sector numbers }
    RunNext, RunLeft:integer;
    Fragment:integer;
  end;

const
  FirstScenario = scSpinUp;
  LastScenario = scGameLoad;
  RandomReads = 200;
  GameFragments = 24;

function ScenarioName(kind:TScenarioKind):string;
function ScenarioHint(kind:TScenarioKind):string;
procedure StartScenario(var run:TScenarioRun; kind:TScenarioKind);
{ The next step; false when the scenario is over }
function NextStep(var run:TScenarioRun; var step:TStep):boolean;
{ Logical sector (0 = cylinder 0, head 0, sector 1) to a position }
procedure LogicalToCHS(logical:integer; var cylinder, head, sector:byte);
function TotalSectors:integer;

{ --------- implementation --------- }
implementation

const
  Names: array[TScenarioKind] of string[20] = (
    'Spin-up and idle', 'Recalibrate', 'Single steps', 'Short seeks', 'Full stroke',
    'Butterfly', 'Sequential read', 'Random read', 'Game loading');
  Hints: array[TScenarioKind] of string[60] = (
    'Spin-up, idle hum, then the BIOS stops the motor',
    'The head running back to cylinder 0',
    'One step at a time: separate clicks',
    'Back and forth near the middle: short buzzes',
    'First cylinder to last and back: the longest seek',
    'Out and in, meeting in the middle',
    'Every track in order, as DISKCOPY reads',
    'Sectors all over the disk: a busy head',
    'A fragmented program loading from floppy');
  ShortSeekCylinders: array[0..11] of shortint = (0, 3, 0, 5, -2, 4, -4, 1, 6, -3, 2, 0);
  StepPauseMs = 400;

function ScenarioName(kind:TScenarioKind):string;
begin
  ScenarioName := Names[kind];
end;

function ScenarioHint(kind:TScenarioKind):string;
begin
  ScenarioHint := Hints[kind];
end;

function TotalSectors:integer;
begin
  TotalSectors := integer(Geometry.Cylinders) * Geometry.Heads * Geometry.Sectors;
end;

function LastCylinder:byte;
begin
  LastCylinder := Geometry.Cylinders - 1;
end;

procedure LogicalToCHS(logical:integer; var cylinder, head, sector:byte);
var
  track:integer;
begin
  track := logical div Geometry.Sectors;
  sector := logical mod Geometry.Sectors + 1;
  head := track mod Geometry.Heads;
  cylinder := track div Geometry.Heads;
end;

{ A Park-Miller style generator in 16-bit friendly arithmetic: 0..range-1 }
function NextRandom(var run:TScenarioRun; range:integer):integer;
begin
  run.Seed := ( run.Seed * 1103 + 12345 ) and $7FFFFF;
  NextRandom := ( run.Seed shr 7 ) mod range;
end;

procedure StartScenario(var run:TScenarioRun; kind:TScenarioKind);
begin
  run.Kind := kind;
  run.Index := 0;
  run.Seed := 1987;
  run.RunNext := 0;
  run.RunLeft := 0;
  run.Fragment := 0;
end;

procedure Read(var step:TStep; cylinder, head, sector, count:byte);
begin
  step.Kind := skRead;
  step.Cylinder := cylinder;
  step.Head := head;
  step.Sector := sector;
  step.Count := count;
  step.WaitMs := 0;
end;

procedure ReadOne(var step:TStep; cylinder:byte);
begin
  Read(step, cylinder, 0, 1, 1);
end;

procedure Wait(var step:TStep; ms:word);
begin
  step.Kind := skWait;
  step.Cylinder := 0;
  step.Head := 0;
  step.Sector := 0;
  step.Count := 0;
  step.WaitMs := ms;
end;

procedure Reset(var step:TStep);
begin
  Wait(step, 0);
  step.Kind := skReset;
end;

function Clamp(cylinder:integer):byte;
begin
  if ( cylinder < 0 ) then cylinder := 0;
  if ( cylinder > LastCylinder ) then cylinder := LastCylinder;
  Clamp := cylinder;
end;

{ Game loading: the FAT and directory, then the file in fragments of a few
  sectors scattered over the disk, each read a track's worth at most at a time }
function GameLoadStep(var run:TScenarioRun; var step:TStep):boolean;
var
  cylinder, head, sector:byte;
  count:integer;
begin
  GameLoadStep := true;
  case run.Index of
    0: begin Read(step, 0, 0, 2, Geometry.Sectors div 2); exit; end;   { The FAT }
    1: begin Read(step, 0, Geometry.Heads - 1, 2, 7); exit; end;        { The root directory }
  end;

  if ( run.RunLeft = 0 ) then begin
    if ( run.Fragment >= GameFragments ) then begin
      GameLoadStep := false;
      exit;
    end;
    inc(run.Fragment);
    { Mostly forwards, as DOS fills a disk, now and then back to an earlier gap }
    run.RunLeft := 2 + NextRandom(run, 12);
    if ( NextRandom(run, 4) = 0 ) or ( run.RunNext = 0 ) then
      run.RunNext := Geometry.Sectors * 2 + NextRandom(run, TotalSectors - Geometry.Sectors * 4)
    else
      run.RunNext := run.RunNext + run.RunLeft + NextRandom(run, Geometry.Sectors * 6);
    if ( run.RunNext + run.RunLeft > TotalSectors ) then run.RunNext := TotalSectors - run.RunLeft;
  end;

  LogicalToCHS(run.RunNext, cylinder, head, sector);
  count := run.RunLeft;
  if ( sector + count - 1 > Geometry.Sectors ) then count := Geometry.Sectors - sector + 1;
  Read(step, cylinder, head, sector, count);
  inc(run.RunNext, count);
  dec(run.RunLeft, count);
end;

function NextStep(var run:TScenarioRun; var step:TStep):boolean;
var
  i, half, track:integer;
  more:boolean;
begin
  i := run.Index;
  more := true;
  case run.Kind of
    scSpinUp:
      case i of
        0: ReadOne(step, 0);
        1: Wait(step, 5000);  { The BIOS stops the motor after about 2 s }
      else more := false;
      end;

    scRecalibrate:
      { Out to the far end, then a reset: the BIOS recalibrates on the next read }
      case i of
        0: ReadOne(step, LastCylinder);
        1: Wait(step, 800);
        2: Reset(step);
        3: ReadOne(step, 0);
        4: Wait(step, 800);
      else more := false;
      end;

    scSingleSteps:
      if ( i < 22 ) then begin
        if ( i mod 2 = 0 ) then ReadOne(step, Clamp(i div 2)) else Wait(step, StepPauseMs);
      end
      else more := false;

    scShortSeeks:
      if ( i < 2 * ( High(ShortSeekCylinders) + 1 ) ) then begin
        if ( i mod 2 = 0 ) then
          ReadOne(step, Clamp(Geometry.Cylinders div 2 + ShortSeekCylinders[i div 2]))
        else
          Wait(step, 150);
      end
      else more := false;

    scFullStroke:
      if ( i < 20 ) then begin
        case i mod 4 of
          0: ReadOne(step, 0);
          2: ReadOne(step, LastCylinder);
        else Wait(step, 300);
        end;
      end
      else more := false;

    scButterfly:
      begin
        half := ( Geometry.Cylinders + 1 ) div 2;
        if ( i < half * 2 ) then begin
          if ( i mod 2 = 0 ) then ReadOne(step, i div 2) else ReadOne(step, LastCylinder - i div 2);
        end
        else more := false;
      end;

    scSequential:
      if ( i < integer(Geometry.Cylinders) * Geometry.Heads ) then begin
        track := i;
        Read(step, track div Geometry.Heads, track mod Geometry.Heads, 1, Geometry.Sectors);
      end
      else more := false;

    scRandom:
      if ( i < RandomReads ) then
        Read(step, NextRandom(run, Geometry.Cylinders), NextRandom(run, Geometry.Heads),
             1 + NextRandom(run, Geometry.Sectors), 1)
      else more := false;

    scGameLoad:
      more := GameLoadStep(run, step);
  end;
  if ( more ) then inc(run.Index);
  NextStep := more;
end;

end.
