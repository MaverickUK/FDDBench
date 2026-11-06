# Changelog

All notable changes to FDDBench. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [SemVer](https://semver.org/).

## [Unreleased]

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
