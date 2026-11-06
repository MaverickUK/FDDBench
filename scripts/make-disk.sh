#!/usr/bin/env bash
# A 1.44 MB FAT12 floppy image with a few files, for DOSBox-X.
# Usage: scripts/make-disk.sh out.img    Needs mtools (brew install mtools).
set -euo pipefail
out=$1
rm -f "$out"
mformat -C -f 1440 -v FDDBENCH -i "$out" ::
# A file across most of the disk, so reads have something to find
head -c 1200000 /dev/urandom > "$out.data"
mcopy -i "$out" "$out.data" ::GAME.DAT
rm -f "$out.data"
printf 'FDDBench test disk\r\n' > "$out.txt"
mcopy -i "$out" "$out.txt" ::README.TXT
rm -f "$out.txt"
