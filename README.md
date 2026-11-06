# FDDBench

**Floppy drive sounds and benchmark for DOS.** FDDBench runs a series of operations on a floppy drive, each chosen for how it sounds: spin-up, single steps, seeks short and long, whole-disk reads, a program loading. As it goes, a disk map in the style of Norton's disk tools shows every sector being read.

![FDDBench showing the game loading scenario: a disk map of a 1.44 MB disk, with the sectors read so far in green](docs/fddbench-game-loading.png)

It was written to show how realistic [FDDSynthPro](https://github.com/MaverickUK/FDDSynthPro), a floppy drive emulator that plays a real drive's sounds, sounds on a real PC. It works with any drive, real or emulated, so the same run can compare the two. The look is [GameMinder](https://github.com/MaverickUK/GameMinder)'s.

## Running it

```
FDDBENCH [A: | B:] [/AUTO] [/WRITE] [/DUMP:file]
```

Put any formatted disk in the drive and run `FDDBENCH` (drive A: unless you name B:). Press **1** to **9** for a scenario, **A** to run them all, **B** for the benchmark, **Esc** to stop one or to quit, **Space** to pause.

| | Scenario | What to listen for |
|---|---|---|
| 1 | Spin-up and idle | Spin-up, the idle hum, then spin-down when the BIOS stops the motor |
| 2 | Recalibrate | The head running back to cylinder 0 |
| 3 | Single steps | One step at a time: separate clicks |
| 4 | Short seeks | Back and forth near the middle: short buzzes |
| 5 | Full stroke | First cylinder to last and back: the longest seek |
| 6 | Butterfly | Out and in, meeting in the middle |
| 7 | Sequential read | Every track in order, as DISKCOPY reads |
| 8 | Random read | Sectors all over the disk: a busy head |
| 9 | Game loading | A fragmented program loading from floppy |
| 0 | Disk change | Eject and insert: does the PC see the change? |
| W | Write and verify | The last ten cylinders written, then read back |

Scenarios 1 to 9 only read, through the BIOS, so the disk's contents don't matter and nothing on it changes; **A** runs them all. Each one visits the same sectors every time it runs, so it sounds the same every time.

**Write and verify writes over the last ten cylinders of the disk**: use a disk you don't need. It says so and asks before the first write. Each sector gets a pattern naming its cylinder, head and sector, different every run, and is read back and compared: written cells turn yellow, then green once they read back as written.

In the map, each cell is three sectors of one track; each group of cells is a cylinder (head 0, then head 1 in cyan), and each row starts with its first cylinder's number. Green is read, a flashing cell is where the head is now, and a red X is a sector the BIOS couldn't read.

Every run is logged to `FDDBENCH.LOG` beside the program, with the time of day, to line up with the drive's own log. The log is written between scenarios, never during one, so it doesn't add seeks of its own.

## The benchmark

**B** measures what the drive and the PC give together. A floppy can't say when a seek has finished, so every figure is the time from one read finishing to the next:

| | How | A real drive |
|---|---|---|
| Rotation | 20 reads of the same sector: each waits one revolution | 300 RPM (360 for a 1.2 MB 5.25") |
| Sequential read | The whole disk, a track a read | Close to 1 revolution a track, plus the steps |
| Track-to-track | Sector 1 on one cylinder, then each sector in turn on the next: the shortest gap | The PC's step rate and head settle time, to a sector |
| Full stroke | The same, first cylinder to last | |
| Average access | 50 random single sectors | About half a revolution plus the seek |
| Errors / retries | Reads the BIOS gave up on, and those that needed a second try | 0 / 0 |

Run it on the same PC with a real drive and with an emulated one to compare them: a slow track change or a missed revolution shows up in the sequential read's revolutions a track.

## Unattended runs

`/AUTO` runs the read scenarios and the benchmark, then exits (`/WRITE` adds write and verify, without asking); `/DUMP:file` then saves the final screen's text (the smoke test uses both).

It runs on any PC from an 8088 up, in text mode, on CGA, EGA, VGA or MDA.

## Status

Version 0.3.0 has the scenarios, the map, the benchmark, write and verify, and the disk-change check. Next, from the [design](DESIGN.md): themes, help, and a demo video.

## Building

See [BUILD.md](BUILD.md).

## Licence

GPL-3.0, as GameMinder, whose code it borrows.
