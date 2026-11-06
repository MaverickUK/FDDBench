# Building FDDBench

FDDBench builds with Free Pascal's i8086-msdos cross compiler (large memory model), as [GameMinder](https://github.com/MaverickUK/GameMinder) is released. CI does the same: [ci.yml](.github/workflows/ci.yml).

```
make          # build/dos/FDDBENCH.EXE
make test     # unit tests, natively (Homebrew or distro fpc)
make run      # DOSBox-X, with a 1.44 MB floppy image as A:
make smoke    # /AUTO in DOSBox-X, then checks the log and the final screen
```

`make run` and `make smoke` need DOSBox-X and mtools (`brew install --cask dosbox-x; brew install mtools`).

## The cross compiler

Built once from FPC 3.2.2's source into `~/fpc-msdos`:

```
curl -sSLO https://downloads.sourceforge.net/project/freepascal/Source/3.2.2/fpc-3.2.2.source.tar.gz
tar xzf fpc-3.2.2.source.tar.gz
make -C fpc-3.2.2 crossall crossinstall CPU_TARGET=i8086 OS_TARGET=msdos \
  CROSSOPT="-WmLarge -CX -XX" BINUTILSPREFIX= INSTALL_PREFIX=$HOME/fpc-msdos
```

On an Apple Silicon Mac it needs two more options, `OPT="-XR$(xcrun --show-sdk-path) -dFPC_SOFT_FPUX80 -Fu$PWD/fpc-3.2.2/rtl/inc"`:
- `-XR` points the linker at the macOS SDK (3.2.2's bootstrap can't find libc on recent macOS);
- `-dFPC_SOFT_FPUX80` and `-Fu.../rtl/inc` give the compiler software 80-bit floats, which an i8086 target needs and an ARM host lacks.

The units are smart-linked (`-CX -XX`), so programs link with `-XX` too.

## Source layout

| File | |
|---|---|
| `FDDBENCH.PAS` | Startup, command line, menu, running scenarios, the log |
| `SCENARIO.PAS` | The scenarios, as steps worked out from the disk's geometry |
| `DISKMAP.PAS` | The map's layout and each cell's state |
| `MEASURE.PAS` | Timing arithmetic and the text for speeds, times, RPM |
| `VIEW.PAS` | The screen: frame, map, heading, status, footer |
| `BIOSDISK.PAS` | INT 13h: reset, read, write, geometry, disk change; the DMA-safe buffer |
| `TIMER.PAS` | Microsecond timing from the PIT |
| `FPUFIX.PAS` | From GameMinder: starts without an FPU under Free Pascal |

`SCENARIO`, `DISKMAP` and `MEASURE` don't touch the screen or the BIOS, so `tests/TESTS.PAS` tests them on any OS.
