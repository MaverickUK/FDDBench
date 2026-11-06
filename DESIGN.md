# FDDBench design

FDDBench is a DOS program for testing a floppy drive on a real PC. It runs a series of operations, each chosen for how it sounds, and it benchmarks the drive. A disk map in the style of Norton's disk tools shows which sectors are being read or written as it happens.

It was written to show off [FDDSynthPro](https://github.com/MaverickUK/FDDSynthPro), a floppy drive emulator that plays the sounds of a real drive. It works with any drive, real or emulated, so the same run can compare the two.

## Decisions

| | |
|---|---|
| Language | Turbo Pascal 7 / Free Pascal i8086-msdos, as [GameMinder](https://github.com/MaverickUK/GameMinder). Releases are built by CI with Free Pascal. |
| Oldest PC | 8088 / XT: real mode, text mode, BIOS calls only. |
| Disk access | BIOS INT 13h, never DOS files. Each scenario decides exactly which cylinder, head and sector the drive visits, so a run sounds the same every time. Any formatted disk works. |
| Writes | Allowed, but only after a warning naming the drive, with the default answer No. Write scenarios are marked in the menu. |
| Look | GameMinder's: its frame, colours, themes (`THEMES.TXT`) and heading bars. |

## The screen

80×25 text, the same on CGA, EGA, VGA and MDA (Mono theme).

```
 FDDBench 0.1.0              Drive A: 1.44 MB  80 cyl  2 heads  18 sectors
╒═Disk map═══════════════════════════════════════════════════════════════════╕
│     +0 h0 h1     +1           +2           +3           +4                 │
│ C00 ░░░░░░▓▓▓▓▓▓ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░      │
│ C05 ████████████ ████████████ ██████▒▒▒▒▒▒ ░░░░░░░░░░░░ ░░░░░░░░░░░░      │
│ C10 ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░      │
│ ...                         (16 rows: cylinders 0-79)                      │
│ C75 ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░░░░░░░░░░░ ░░X░░░░░░░░░      │
├─Sequential read──────────────────────────────────────────────────────────────┤
│ Cyl 12  Head 1  Sector 7-9   Reading      Elapsed  0:23.4   Steps   12     │
│ Read  396 KB   Written 0 KB   Errors 0    Speed   17.0 KB/s   Seeks    1   │
│ █ read  ▓ written  ▒ now  ░ not yet  X error                               │
╘════════════════════════════════════════════════════════════════════════════╛
 Esc stop   Space pause   F1 help   F2 scenarios   F3 benchmark   F10 log
```

**The map.** One cell is three sectors, so a track is six cells and a cylinder is twelve (head 0, then head 1). With five cylinders a row, sixteen rows hold a 1.44 MB disk. Three divides every PC format's sectors per track (9, 15, 18), so the same map fits 360 KB (40 cylinders: 4 rows of 10), 720 KB and 1.2 MB disks. Formats with more sectors (1.68 MB DMF, 2.88 MB) get six or more sectors a cell, to stay within 16 rows.

A cell is drawn as soon as its sectors are done:

| Mark | Colour (Classic) | Meaning |
|---|---|---|
| `░` | Light grey | Not visited yet in this scenario |
| `▒` | White, flashing | The head is here now |
| `█` | Light green | Read |
| `▓` | Yellow | Written |
| `X` | Light red | Error: the BIOS gave up after its retries |

Seeks with no read in between leave a trail: the cell under the head flashes as it moves, so a full-stroke seek can be seen sweeping down the map.

**The status lines** give the position (cylinder, head, sectors), the operation, the elapsed time, how much has been read and written, errors, speed, steps and seeks. The heading bar between the map and the status lines names the scenario.

## Scenarios

Each one is a menu entry (F2). "Run all" plays them in order, with a short pause between them so each can be heard on its own. Write scenarios are marked `W` and skipped by "Run all" unless writes were allowed at the start.

| Scenario | What it does | What to listen for |
|---|---|---|
| Spin-up and idle | Reads one sector, then waits through the BIOS motor timeout | Spin-up, idle hum, spin-down after about 2 s |
| Recalibrate | Resets the controller (INT 13h AH=00), which seeks to cylinder 0 | The head running back to track 0 |
| Single steps | Reads cylinder 0, 1, 2 ... 10 with a pause between | Separate clicks |
| Short seeks | Back and forth between nearby cylinders | Short buzzes |
| Full stroke | 0 → 79 → 0, five times | The longest seek |
| Butterfly | 0 → 79 → 1 → 78 → 2 ..., the classic seek test | Seeks shortening towards the middle |
| Sequential read | Every track in order, as DISKCOPY reads | Steady step-per-track rhythm |
| Random read | 200 sectors at random | A busy head |
| Game loading | Reads clusters scattered across the disk in the order a fragmented file would need them | A program loading from floppy |
| Disk change | Asks the BIOS for the disk-change line (AH=16h), asks for the disk to be swapped, and checks again | Eject and insert, if the drive plays them |
| `W` Write and verify | Writes a pattern to every sector of a cylinder range, then reads it back and compares | Writes sound like reads on a 3.5" drive; the map turns yellow |
| `W` Format track | Formats one track (AH=05) and verifies it | |

## Benchmark

F3 runs the benchmark: read only, so any disk will do. Each test is repeated and the median reported.

| Test | How |
|---|---|
| Rotation (RPM) | Reads the same sector 20 times; each read waits a whole revolution for it to come round again |
| Track-to-track | Alternates reads between neighbouring cylinders, less the rotation's average wait |
| Full stroke | Alternates reads between cylinder 0 and the last |
| Average access | Reads at random cylinders and sectors |
| Sequential | Reads the whole disk a track at a time (KB/s) |

Times come from the PIT (the 8253's channel 0, latched), not the BIOS tick: 55 ms ticks are too coarse for a step of 3 ms. The whole ticks are FDDBench's own too, counted by its INT 08h handler before it chains to the BIOS's: a BIOS may keep its count at 0040:006C in step with the CMOS clock, so a fast timer (the Evesham's, 1.55%) shows over short times but not long ones, and the timer check, made with the BIOS's count, would miss it. The results are compared with what a real drive of the type should give (300 RPM, 3 ms track-to-track for a 1.44 MB drive), so a slow or noisy result stands out.

## The log

Every scenario and the benchmark append to `FDDBENCH.LOG` beside the program: the time of day, the scenario, each operation's start and result, and the benchmark's figures. With FDDSynthPro, the drive's serial log can be lined up against it by time, and its `scripts/check_log.py` reads the drive's side.

## Source layout

Following GameMinder's:

| Unit | |
|---|---|
| `FDDBENCH.PAS` | Startup, command line, main loop |
| `SCREEN.PAS` | Frame, heading bars, footer (from GameMinder's) |
| `THEMES.PAS` | Colour themes (from GameMinder's, `THEMES.TXT`) |
| `DISKMAP.PAS` | The map: cell layout for a geometry, cell states, drawing |
| `BIOSDISK.PAS` | INT 13h: reset, read, write, verify, format, drive type, disk change |
| `TIMER.PAS` | PIT timing in microseconds |
| `SCENARIO.PAS` | The scenarios as lists of steps (seek, read, write, wait, ask) |
| `BENCH.PAS` | The benchmark and its statistics |
| `RUNLOG.PAS` | `FDDBENCH.LOG` |

`DISKMAP`'s layout, `SCENARIO`'s step lists, `BENCH`'s statistics and `RUNLOG`'s formatting don't touch the screen or the BIOS, so they're unit tested natively with Free Pascal, as GameMinder's logic units are.

## Testing

- **Unit tests** on the Mac and in CI (`fpc -Mtp`).
- **DOSBox-X** smoke test in CI: a floppy image mounted as A:, FDDBench run with `/AUTO` (run all, write to the log, exit), and the log checked. DOSBox-X emulates INT 13h, so this proves the program end to end, though not its timings.
- **FDDSynthPro's rig** with a real PC is the final check, with the drive's serial log beside FDDBench's.

## Plan

1. The screen and the map, driven by the sequential read. Read only.
2. The other read scenarios, "Run all" and the log.
3. The benchmark.
4. Write scenarios behind the warning.
5. Themes, help, DOSBox-X recording of a demo for the README.
