Unit BiosDisk;
{-----------------------------
The floppy through the BIOS (INT 13h): reset, read, write, the drive's
type, the disk-change line, and the disk's geometry from its boot sector

Every transfer goes through one buffer, placed so it never crosses a 64 KB
boundary in physical memory: the PC's DMA controller can't carry over into
the next 64 KB page, and the BIOS fails such a transfer with status 09h.

Floppy reads fail now and then for no fault of the disk (the motor still
spinning up, a disk change just seen), so each call is tried up to three
times with a reset between, as the BIOS's documentation advises.
------------------------------}

{ --------- interface -------- }
interface

const
  SectorBytes = 512;
  MaxTrackBytes = 36 * SectorBytes;
  Tries = 3;

type
  TBytes = array[0..MaxTrackBytes - 1] of byte;
  PBytes = ^TBytes;

var
  Buffer:PBytes;
  Retries:longint;  { Calls that needed more than one try }

{ False if there's no memory for the buffer }
function InitBuffer:boolean;
function ResetDrive(drive:byte):byte;
{ 0 if all went well, else the BIOS's status }
function ReadSectors(drive, cylinder, head, sector, count:byte):byte;
function WriteSectors(drive, cylinder, head, sector, count:byte):byte;
{ The drive's type from INT 13h AH=08h (AT BIOS); false on an XT BIOS }
function DriveGeometry(drive:byte; var cylinders, heads, sectors, kind:byte):boolean;
{ The disk's geometry from its boot sector; false if it doesn't hold one }
function DiskGeometry(drive:byte; var cylinders, heads, sectors:byte):boolean;
{ INT 13h AH=16h: 0 not changed, 6 changed, other values an error }
function ChangeLine(drive:byte):byte;
function StatusText(status:byte):string;
function DriveKindText(kind:byte):string;

{ --------- implementation --------- }
implementation
uses
    Dos;

var
  block:pointer;

function InitBuffer:boolean;
var
  physical:longint;
begin
  InitBuffer := false;
  if ( MaxAvail < 2 * MaxTrackBytes + 16 ) then exit;
  GetMem(block, 2 * MaxTrackBytes);
  physical := longint(Seg(block^)) * 16 + Ofs(block^);
  if ( ( physical and $FFFF ) + MaxTrackBytes > $10000 ) then
    physical := ( physical or $FFFF ) + 1;  { Start at the next 64 KB page: there's room after it }
  Buffer := Ptr(physical shr 4, physical and $F);
  InitBuffer := true;
end;

function ResetDrive(drive:byte):byte;
var
  regs:Registers;
begin
  regs.AH := $00;
  regs.DL := drive;
  Intr($13, regs);
  ResetDrive := regs.AH;
end;

function Transfer(command, drive, cylinder, head, sector, count:byte):byte;
var
  regs:Registers;
  try:integer;
begin
  for try := 1 to Tries do begin
    regs.AH := command;
    regs.AL := count;
    regs.CH := cylinder;
    regs.CL := sector;
    regs.DH := head;
    regs.DL := drive;
    regs.ES := Seg(Buffer^);
    regs.BX := Ofs(Buffer^);
    Intr($13, regs);
    if ( regs.Flags and FCarry = 0 ) then begin
      if ( try > 1 ) then inc(Retries);
      Transfer := 0;
      exit;
    end;
    Transfer := regs.AH;
    if ( regs.AH = 0 ) then Transfer := $FF;  { Carry with no status: call it a failure anyway }
    ResetDrive(drive);
  end;
end;

function ReadSectors(drive, cylinder, head, sector, count:byte):byte;
begin
  ReadSectors := Transfer($02, drive, cylinder, head, sector, count);
end;

function WriteSectors(drive, cylinder, head, sector, count:byte):byte;
begin
  WriteSectors := Transfer($03, drive, cylinder, head, sector, count);
end;

function DriveGeometry(drive:byte; var cylinders, heads, sectors, kind:byte):boolean;
var
  regs:Registers;
begin
  DriveGeometry := false;
  regs.AH := $08;
  regs.DL := drive;
  regs.ES := 0;
  regs.DI := 0;
  regs.BL := 0;
  Intr($13, regs);
  if ( regs.Flags and FCarry <> 0 ) or ( regs.BL = 0 ) then exit;
  kind := regs.BL;
  cylinders := regs.CH + 1;
  sectors := regs.CL and $3F;
  heads := regs.DH + 1;
  DriveGeometry := ( sectors > 0 );
end;

function Word16(offset:word):word;
begin
  Word16 := Buffer^[offset] or ( word(Buffer^[offset + 1]) shl 8 );
end;

function DiskGeometry(drive:byte; var cylinders, heads, sectors:byte):boolean;
var
  total:longint;
  spt, nheads:word;
begin
  DiskGeometry := false;
  if ( ReadSectors(drive, 0, 0, 1, 1) <> 0 ) then exit;
  if ( Word16(11) <> SectorBytes ) then exit;
  spt := Word16(24);
  nheads := Word16(26);
  total := Word16(19);
  if ( total = 0 ) then total := longint(Word16(32)) or ( longint(Word16(34)) shl 16 );
  if ( spt < 8 ) or ( spt > 36 ) or ( nheads < 1 ) or ( nheads > 2 ) then exit;
  total := total div ( spt * nheads );
  if ( total < 1 ) or ( total > 84 ) then exit;
  cylinders := total;
  heads := nheads;
  sectors := spt;
  DiskGeometry := true;
end;

function ChangeLine(drive:byte):byte;
var
  regs:Registers;
begin
  regs.AH := $16;
  regs.DL := drive;
  Intr($13, regs);
  if ( regs.Flags and FCarry = 0 ) then ChangeLine := 0 else ChangeLine := regs.AH;
end;

function HexByte(b:byte):string;
const
  digits:string[16] = '0123456789ABCDEF';
begin
  HexByte := digits[b shr 4 + 1] + digits[b and $F + 1];
end;

function StatusText(status:byte):string;
var
  s:string;
begin
  case status of
    $00: s := 'OK';
    $01: s := 'bad command';
    $02: s := 'address mark not found';
    $03: s := 'write-protected';
    $04: s := 'sector not found';
    $06: s := 'disk changed';
    $08: s := 'DMA overrun';
    $09: s := 'DMA across 64K';
    $0C: s := 'unknown media';
    $10: s := 'CRC error';
    $20: s := 'controller failed';
    $40: s := 'seek failed';
    $80: s := 'not ready (no disk?)';
  else s := 'error';
  end;
  StatusText := s + ' (' + HexByte(status) + 'h)';
end;

function DriveKindText(kind:byte):string;
begin
  case kind of
    1: DriveKindText := '5.25" 360K';
    2: DriveKindText := '5.25" 1.2M';
    3: DriveKindText := '3.5" 720K';
    4: DriveKindText := '3.5" 1.44M';
    5, 6: DriveKindText := '3.5" 2.88M';
  else DriveKindText := 'unknown';
  end;
end;

begin
  Buffer := nil;
  Retries := 0;
end.
