# Changelog

All notable changes to FDDBench. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.4.1] - 2026-11-06

### Fixed
- **Timings on the Evesham read 1.55% long, and the timer check couldn't see it:** checked against FDDSynthPro's own crystal (its log times every step to the microsecond), FDDBench's rotation read 203.1 ms for 200.0, its track-to-track 33.2 for 32.74 and its full stroke 439.5 for 432.75, while its times over a minute agreed with the drive's to 0.16%. That PC's timer runs fast, and something (its BIOS) keeps the BIOS tick count at 0040:006C in step with the CMOS clock. FDDBench took its ticks from that count, so 0.4.0's timer check, which used them too, would have read about +0.00%. FDDBench now counts the timer's ticks itself, in its own INT 08h handler, which then passes each one on to the BIOS's, so every time it measures is the timer's alone, and the timer check corrects it. The check also times the BIOS's count, and when the two differ the result says so: "PC timer +1.55%, corrected; BIOS clock +0.00%".

## [0.4.0] - 2026-11-06

### Added
- **The benchmark checks the PC's timer** against the CMOS clock (its own 32 kHz crystal) for 5 seconds before it starts, shows how far off it is ("PC timer +1.55%"), and corrects every result by it. On the Evesham, the first real PC to run FDDBench, the rotation came out at 295.4 RPM (203.1 ms) where the drive turns at 300 by its own clock: either that PC's timer runs fast, which some clone boards' do, or FDDBench's arithmetic is out, and this says which. In DOSBox it reads +0.00%. An XT has no CMOS clock: it says so, and corrects nothing.

### Changed
- The benchmark's note on seek times moved to the status line, making room for the timer's result.

### Fixed
- CI may create releases (`contents: write`).

## [0.3.2] - 2026-11-06

### Fixed
- CI installs NASM, which building the cross compiler needs, so releases build. 0.3.1 was tagged but never released.

## [0.3.1] - 2026-11-06

### Fixed
- Write and verify kept the question's heading ("this writes to the disk") while it ran, instead of its own.
- Back at the menu after the benchmark, the map still showed the benchmark's reads.
- The benchmark's explanation was cut off at the right of the screen.

### Added
- A demo video in the README, recorded in DOSBox-X by `scripts/record-demo.sh`.

## [0.3.0] - 2026-11-06

### Added
- **Write and verify (W):** writes a test pattern over the last ten cylinders, a track at a time, then reads it back and compares. Each sector's pattern names its cylinder, head and sector and changes every run, so stale data can't pass. Written cells turn yellow, then green once they read back as written; a sector that reads back different is a red X and a log line. Before the first write it says which cylinders it will write over and asks; the answer holds until FDDBench exits. A write-protected disk stops it with a message.
- **Disk change (0):** reads the disk-change line, asks for the disk to be ejected and put back, and reads it again: says whether the PC saw the change (pin 34 on a PC drive).
- `/WRITE`: with `/AUTO`, also write and verify, without asking.

### Changed
- "Run all" runs the nine read scenarios only: no writes, no questions.

## [0.2.0] - 2026-11-06

### Added
- **The benchmark (B):** rotation (RPM, from 20 reads of one sector), track-to-track and full-stroke times (the shortest gap from a read on one cylinder to a read on the other, to the nearest sector), average access (50 random reads), sequential read (KB/s, and revolutions a track) and the reads that failed or needed a retry. The results replace the map when it finishes, go to the log, and run after the scenarios with `/AUTO`.
- A rotation faster than 600 RPM is flagged as an emulator: DOSBox's floppy turns at about 2,100.

## [0.1.0] - 2026-11-06

### Added
- Nine read scenarios, each chosen for how it sounds: spin-up and idle, recalibrate, single steps, short seeks, full stroke, butterfly, sequential read, random read and game loading. **A** runs them all.
- The disk map: three sectors a cell, a cylinder a group, laid out for any PC format from 160 KB to 2.88 MB. Cells turn green as they're read, flash while the head is over them, and show a red X for a sector the BIOS couldn't read.
- Status lines: position, operation, elapsed time, KB read, errors, speed, steps and seeks, timed to the microsecond from the PIT.
- `FDDBENCH.LOG`, written between scenarios.
- `/AUTO` and `/DUMP:file` for unattended runs.
