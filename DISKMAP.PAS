Unit DiskMap;
{-----------------------------
The disk map: where each sector of the disk is drawn, and what has
happened to it

A cell is a few sectors of one track (SectorsPerCell, 3 for every common PC
format). A cylinder is a group of cells: head 0's track, then head 1's, then
a space. Each row of the map starts with its first cylinder's number and
holds as many cylinders as fit across, so a 1.44 MB disk (18 sectors, 6
cells a track) is 5 cylinders a row, 16 rows:

  C00 ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░
  C05 ...

No screen here: positions are columns and rows inside the map's area, so
this is unit tested on any OS. MapView draws it.
------------------------------}

{ --------- interface -------- }
interface

const
  MapWidth = 76;     { Columns inside the frame, less a space either side }
  MapRows = 16;      { Rows for cylinders }
  LabelWidth = 4;    { "C00 " }
  MaxCells = 2048;
  MaxCylinders = 84;
  MaxHeads = 2;
  MaxSectors = 36;

type
  TGeometry = record
    Cylinders:byte;   { 40 or 80, up to 84 }
    Heads:byte;       { 1 or 2 }
    Sectors:byte;     { Per track: 8, 9, 15, 18, 21, 36 }
  end;

  TCellState = (csNotYet, csRead, csWritten, csError);

var
  Geometry:TGeometry;
  SectorsPerCell:byte;
  CellsPerTrack:byte;
  CylindersPerRow:byte;
  Cells:array[0..MaxCells - 1] of TCellState;

{ Lays the map out for a disk; false if it can't be drawn (too big or empty) }
function SetGeometry(cylinders, heads, sectors:byte):boolean;
function CellCount:integer;
function CellOf(cylinder, head, sector:byte):integer;
{ Where a cell is drawn: column 0 is the map's first, row 0 its first }
function CellColumn(cell:integer):byte;
function CellRow(cell:integer):byte;
function RowsUsed:byte;
{ Columns the map takes: its labels and its widest row }
function UsedWidth:byte;
function RowLabel(row:byte):string;
{ The first and last cells sectors first..first+count-1 of a track cover }
procedure CellRange(cylinder, head, first, count:byte; var fromCell, toCell:integer);
procedure ClearCells;
{ Marks sectors as read, written or failed. An error stays until cleared }
procedure MarkSectors(cylinder, head, first, count:byte; state:TCellState);

{ --------- implementation --------- }
implementation

function CellsPerCylinder:byte;
begin
  CellsPerCylinder := Geometry.Heads * CellsPerTrack;
end;

function SetGeometry(cylinders, heads, sectors:byte):boolean;
var
  rows:integer;
begin
  SetGeometry := false;
  if ( cylinders = 0 ) or ( cylinders > MaxCylinders ) or ( heads = 0 ) or ( heads > MaxHeads )
     or ( sectors = 0 ) or ( sectors > MaxSectors ) then exit;

  Geometry.Cylinders := cylinders;
  Geometry.Heads := heads;
  Geometry.Sectors := sectors;

  { Three sectors a cell, or six, nine... until the disk fits the rows }
  SectorsPerCell := 3;
  repeat
    CellsPerTrack := ( sectors + SectorsPerCell - 1 ) div SectorsPerCell;
    CylindersPerRow := ( MapWidth - LabelWidth + 1 ) div ( CellsPerCylinder + 1 );
    if ( CylindersPerRow > 0 ) then
      rows := ( cylinders + CylindersPerRow - 1 ) div CylindersPerRow
    else
      rows := MapRows + 1;
    if ( rows > MapRows ) then inc(SectorsPerCell, 3);
  until ( rows <= MapRows ) or ( SectorsPerCell > sectors + 3 );

  if ( rows > MapRows ) or ( CellCount > MaxCells ) then exit;
  ClearCells;
  SetGeometry := true;
end;

function CellCount:integer;
begin
  CellCount := integer(Geometry.Cylinders) * CellsPerCylinder;
end;

function CellOf(cylinder, head, sector:byte):integer;
begin
  CellOf := ( integer(cylinder) * Geometry.Heads + head ) * CellsPerTrack + ( sector - 1 ) div SectorsPerCell;
end;

function CellColumn(cell:integer):byte;
var
  cylinder, inCylinder:integer;
begin
  cylinder := cell div CellsPerCylinder;
  inCylinder := cell mod CellsPerCylinder;
  CellColumn := LabelWidth + ( cylinder mod CylindersPerRow ) * ( CellsPerCylinder + 1 ) + inCylinder;
end;

function CellRow(cell:integer):byte;
begin
  CellRow := ( cell div CellsPerCylinder ) div CylindersPerRow;
end;

function RowsUsed:byte;
begin
  RowsUsed := ( Geometry.Cylinders + CylindersPerRow - 1 ) div CylindersPerRow;
end;

function UsedWidth:byte;
begin
  UsedWidth := LabelWidth + CylindersPerRow * ( CellsPerCylinder + 1 ) - 1;
end;

function RowLabel(row:byte):string;
var
  s:string;
begin
  Str(integer(row) * CylindersPerRow, s);
  if ( length(s) < 2 ) then s := '0' + s;
  RowLabel := 'C' + s;
end;

procedure CellRange(cylinder, head, first, count:byte; var fromCell, toCell:integer);
begin
  fromCell := CellOf(cylinder, head, first);
  toCell := CellOf(cylinder, head, first + count - 1);
end;

procedure ClearCells;
var
  i:integer;
begin
  for i := 0 to MaxCells - 1 do Cells[i] := csNotYet;
end;

procedure MarkSectors(cylinder, head, first, count:byte; state:TCellState);
var
  i, fromCell, toCell:integer;
begin
  if ( count = 0 ) then exit;
  CellRange(cylinder, head, first, count, fromCell, toCell);
  for i := fromCell to toCell do
    if ( Cells[i] <> csError ) or ( state = csNotYet ) then Cells[i] := state;
end;

end.
