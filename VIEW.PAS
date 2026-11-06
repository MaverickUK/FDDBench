Unit View;
{-----------------------------
The screen: the frame, the disk map, the scenario's heading and the status
lines, in GameMinder's Classic colours

  1      title: FDDBench and the drive
  2      frame top, "Disk map"
  3      the cylinder offset of each group (+0 +1 ...)
  4-19   the map (DiskMap)
  20     the heading bar: the scenario
  21-23  status lines
  24     frame bottom
  25     the keys

Cells are drawn one at a time as their sectors are done, so the map keeps
up on an XT. The last column of the last row is never written: Crt would
scroll the screen.
------------------------------}

{ --------- interface -------- }
interface

uses
    DiskMap;

const
  MapTop = 4;
  HeadingRow = 20;
  StatusRow = 21;
  FooterRow = 25;

  { Classic theme }
  ColBackground = 1;   { Blue }
  ColText = 15;        { White }
  ColFrame = 15;
  ColHeadingText = 14; { Yellow }
  ColHeadingBack = 4;  { Red }
  ColLabel = 11;       { Light cyan }
  ColNotYet = 7;       { Light grey: head 0 }
  ColNotYet1 = 3;      { Cyan: head 1, so the sides of a cylinder can be told apart }
  ColRead = 10;        { Light green }
  ColWritten = 14;     { Yellow }
  ColError = 12;       { Light red }
  ColHead = 15;        { White, flashing }
  ColFooterKey = 14;

procedure InitScreen;
procedure DoneScreen;
procedure DrawTitle(drive:string);
procedure DrawFrame;
procedure DrawMap;
procedure DrawCell(cell:integer);
{ The head is over these cells now: they flash until DrawCell redraws them }
procedure DrawHead(fromCell, toCell:integer);
procedure DrawHeading(text:string);
procedure DrawStatus(line:byte; text:string);
procedure DrawFooter(text:string);
procedure SaveScreenText(fileName:string);

{ --------- implementation --------- }
implementation
uses
    Crt,
    Dos;

{$I VERSION.INC}

const
  Blink = 128;
  CharNotYet = #176;
  CharHead = #177;
  CharWritten = #178;
  CharRead = #219;
  FrameH = #205;
  FrameV = #179;
  FrameTopLeft = #213;
  FrameTopRight = #184;
  FrameBottomLeft = #212;
  FrameBottomRight = #190;
  FrameTeeLeft = #198;
  FrameTeeRight = #181;

var
  savedCursor:word;
  savedMode:word;
  MapLeft:byte;     { Screen column of the map's column 0: the map is centred }

procedure SetCursor(shape:word);
var
  regs:Registers;
begin
  regs.AH := $01;
  regs.CX := shape;
  Intr($10, regs);
end;

procedure InitScreen;
var
  regs:Registers;
begin
  savedMode := LastMode;
  if ( Hi(WindMax) + 1 <> 25 ) then TextMode(LastMode and $FF);
  CheckBreak := false;
  regs.AH := $03;
  regs.BH := 0;
  Intr($10, regs);
  savedCursor := regs.CX;
  SetCursor($2000);  { Hidden }
  TextBackground(ColBackground);
  TextColor(ColText);
  ClrScr;
end;

procedure DoneScreen;
begin
  NormVideo;
  TextBackground(0);
  TextColor(7);
  ClrScr;
  SetCursor(savedCursor);
end;

procedure Put(x, y:byte; text:string; attr:byte);
begin
  GotoXY(x, y);
  TextAttr := attr;
  if ( y = FooterRow ) and ( x + length(text) - 1 >= 80 ) then text[0] := chr(80 - x);
  Write(text);
end;

function Attr(fore, back:byte):byte;
begin
  Attr := ( back shl 4 ) or fore;
end;

function Repeated(c:char; n:integer):string;
var
  s:string;
  i:integer;
begin
  s := '';
  for i := 1 to n do s := s + c;
  Repeated := s;
end;

procedure DrawTitle(drive:string);
var
  title:string;
begin
  title := ' FDDBench ' + AppVersion;
  Put(1, 1, title + Repeated(' ', 80 - length(title)), Attr(ColHeadingText, ColBackground));
  if ( length(drive) > 0 ) then
    Put(80 - length(drive), 1, drive, Attr(ColText, ColBackground));
end;

procedure DrawFrame;
var
  y:byte;
  label1:string;
begin
  label1 := FrameH + ' Disk map ';
  Put(1, 2, FrameTopLeft + label1 + Repeated(FrameH, 78 - length(label1)) + FrameTopRight, Attr(ColFrame, ColBackground));
  for y := 3 to 23 do begin
    if ( y = HeadingRow ) then continue;
    Put(1, y, FrameV, Attr(ColFrame, ColBackground));
    Put(80, y, FrameV, Attr(ColFrame, ColBackground));
  end;
  Put(1, 24, FrameBottomLeft + Repeated(FrameH, 78) + FrameBottomRight, Attr(ColFrame, ColBackground));
end;

function CellLook(cell:integer; var c:char):byte;
begin
  case Cells[cell] of
    csRead:    begin c := CharRead;    CellLook := Attr(ColRead, ColBackground); end;
    csWritten: begin c := CharWritten; CellLook := Attr(ColWritten, ColBackground); end;
    csError:   begin c := 'X';         CellLook := Attr(ColError, ColBackground); end;
  else begin
    c := CharNotYet;
    if ( Geometry.Heads > 1 ) and ( ( cell div CellsPerTrack ) mod Geometry.Heads = 1 ) then
      CellLook := Attr(ColNotYet1, ColBackground)
    else
      CellLook := Attr(ColNotYet, ColBackground);
  end;
  end;
end;

procedure DrawCell(cell:integer);
var
  c:char;
  a:byte;
begin
  a := CellLook(cell, c);
  Put(MapLeft + CellColumn(cell), MapTop + CellRow(cell), c, a);
end;

procedure DrawHead(fromCell, toCell:integer);
var
  cell:integer;
begin
  for cell := fromCell to toCell do
    Put(MapLeft + CellColumn(cell), MapTop + CellRow(cell), CharHead, Attr(ColHead, ColBackground) or Blink);
end;

procedure DrawMap;
var
  row, y, group:byte;
  cell:integer;
  header:string;
  x:integer;
  offset:string;
begin
  MapLeft := 3 + ( MapWidth - UsedWidth ) div 2;

  { Clear the map's area }
  for y := 3 to HeadingRow - 1 do
    Put(2, y, Repeated(' ', 78), Attr(ColText, ColBackground));

  { The offset of each cylinder group, over its first cell }
  header := Repeated(' ', UsedWidth);
  for group := 0 to CylindersPerRow - 1 do begin
    Str(group, offset);
    offset := '+' + offset;
    x := CellColumn(CellOf(group, 0, 1)) + 1;
    if ( x + length(offset) - 1 <= UsedWidth ) then
      Move(offset[1], header[x], length(offset));
  end;
  Put(MapLeft, MapTop - 1, header, Attr(ColLabel, ColBackground));

  for row := 0 to RowsUsed - 1 do
    Put(MapLeft, MapTop + row, RowLabel(row), Attr(ColLabel, ColBackground));
  for cell := 0 to CellCount - 1 do DrawCell(cell);
end;

procedure DrawHeading(text:string);
begin
  if ( length(text) > 74 ) then text[0] := #74;  { Room for the frame either side }
  Put(1, HeadingRow, FrameTeeLeft, Attr(ColFrame, ColBackground));
  Put(2, HeadingRow, FrameH, Attr(ColFrame, ColBackground));
  Put(3, HeadingRow, ' ' + text + ' ', Attr(ColHeadingText, ColHeadingBack));
  Put(3 + length(text) + 2, HeadingRow, Repeated(FrameH, 78 - length(text) - 3) + FrameTeeRight,
      Attr(ColFrame, ColBackground));
end;

procedure DrawStatus(line:byte; text:string);
begin
  if ( length(text) > 77 ) then text[0] := #77;
  Put(3, StatusRow + line, text + Repeated(' ', 77 - length(text)), Attr(ColText, ColBackground));
end;

{ Keys in yellow, their meaning in white: "Esc~stop  1-9~scenario" }
procedure DrawFooter(text:string);
var
  i:integer;
  key:boolean;
  x:byte;
begin
  GotoXY(1, FooterRow);
  TextAttr := Attr(ColText, ColBackground);
  Write(' ');
  x := 2;
  key := true;
  for i := 1 to length(text) do begin
    if ( x >= 80 ) then break;
    if ( text[i] = '~' ) then begin
      key := false;
      TextAttr := Attr(ColText, ColBackground);
      Write(' ');
      inc(x);
      continue;
    end;
    if ( text[i] = '|' ) then begin key := true; continue; end;
    if ( key ) then TextAttr := Attr(ColFooterKey, ColBackground) else TextAttr := Attr(ColText, ColBackground);
    Write(text[i]);
    inc(x);
  end;
  TextAttr := Attr(ColText, ColBackground);
  while ( x < 80 ) do begin Write(' '); inc(x); end;
end;

{ The screen's text, row by row, for tests: FDDBENCH /AUTO /DUMP:file }
procedure SaveScreenText(fileName:string);
var
  f:text;
  row, col:integer;
  line:string;
  segment:word;
begin
  if ( LastMode and $FF ) = Mono then segment := $B000 else segment := $B800;
  Assign(f, fileName);
  {$I-} Rewrite(f); {$I+}
  if ( IOResult <> 0 ) then exit;
  for row := 0 to 24 do begin
    line := '';
    for col := 0 to 79 do line := line + chr(mem[segment:( row * 80 + col ) * 2]);
    while ( length(line) > 0 ) and ( line[length(line)] = ' ' ) do dec(line[0]);
    writeln(f, line);
  end;
  Close(f);
end;

end.
