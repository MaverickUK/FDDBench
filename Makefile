# FDDBench: make (the DOS program), make test (unit tests on this machine),
# make run (in DOSBox-X with a 1.44 MB floppy image as A:), make smoke
# (/AUTO in DOSBox-X, checking the log and the final screen).
#
# The DOS build needs Free Pascal's i8086-msdos cross compiler in
# ~/fpc-msdos (BUILD.md).

FPC_MSDOS ?= $(HOME)/fpc-msdos
PPC := $(FPC_MSDOS)/lib/fpc/3.2.2/ppcross8086
UNITS := $(FPC_MSDOS)/lib/fpc/3.2.2/units/msdos
SOURCES := $(wildcard *.PAS) VERSION.INC

all: build/dos/FDDBENCH.EXE

build/dos/FDDBENCH.EXE: $(SOURCES)
	mkdir -p build/dos
	$(PPC) -Tmsdos -WmLarge -Mtp -O2 -XX -CX -Fu. -Fu"$(UNITS)/*" -FUbuild/dos -o$@ FDDBENCH.PAS

build/tests: $(SOURCES) tests/TESTS.PAS
	mkdir -p build
	fpc -Mtp -Fu. -FUbuild -o$@ tests/TESTS.PAS

test: build/tests
	build/tests

build/disk144.img: scripts/make-disk.sh
	scripts/make-disk.sh $@

run: build/dos/FDDBENCH.EXE build/disk144.img
	scripts/dosbox.sh run

smoke: build/dos/FDDBENCH.EXE build/disk144.img
	scripts/dosbox.sh smoke

clean:
	rm -rf build

.PHONY: all test run smoke clean
