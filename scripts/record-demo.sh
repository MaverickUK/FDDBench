#!/usr/bin/env bash
# Records the README's demo video of FDDBench in DOSBox-X, as GameMinder's
# scripts/record-demo.sh does: scripted keys (AUTOTYPE), captured with
# DX-CAPTURE, then cut with ffmpeg.
#
# The session: the menu, single steps, game loading, part of a sequential
# read, write and verify, the benchmark, its results, and quitting. In
# DOSBox the benchmark takes over a minute and write and verify half that,
# so the final cut plays them faster (6x and 3x), finding where they start
# and end from FDDBENCH.LOG's times.
#
# Usage:   scripts/record-demo.sh [--show]     (--show opens a window to watch)
# Needs:   DOSBox-X, ffmpeg, mtools, build/dos/FDDBENCH.EXE (make)
# Output:  docs/fddbench-demo.mp4 and docs/fddbench-demo.gif
set -euo pipefail
cd "$(dirname "$0")/.."

hide="SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy"
if [ "${1:-}" = --show ]; then hide=; fi
dosbox=${DOSBOX_X:-$(command -v dosbox-x)}

work=build/demo
rm -rf "$work"
mkdir -p "$work/c" "$work/capture"
cp build/dos/FDDBENCH.EXE "$work/c/"
scripts/make-disk.sh "$work/disk.img"

# Keys are paced 2 s apart, but DOSBox-X runs slower while it captures:
# they come about 3.5 s apart. Keys pressed while a scenario runs are
# swallowed, so each waits for the one before to finish:
#   3 single steps (5 s); 9 game loading (5 s); 7 sequential read, Esc after
#   10 s; W, Y write and verify (26 s); B benchmark (72 s); Enter back to
#   the menu; Esc quits. Keep the command under 255 characters.
keys="3 , 9 , 7 , , esc w y , , , , , , , , b"
keys="$keys , , , , , , , , , , , , , , , , , , , , , , enter esc"

for attempt in 1 2 3; do
  rm -rf "$work/capture"/*
  env $hide "$dosbox" -fastlaunch -nomenu -time-limit 240 \
    -set "dosbox captures=$PWD/$work/capture" \
    -c "imgmount a $work/disk.img -t floppy" -c "mount c $work/c" -c "c:" -c "cls" \
    -c "autotype -w 4 -p 2 $keys" \
    -c "dx-capture /v FDDBENCH A:" -c "exit" > "$work/dosbox.log" 2>&1 || true
  if ls "$work"/capture/*.avi > /dev/null 2>&1 && grep -q "Benchmark: Benchmark results" "$work/c/FDDBENCH.LOG"; then break; fi
  echo "The recording didn't finish (attempt $attempt)" >&2
  [ "$attempt" -lt 3 ] || exit 1
done
avi=$(ls "$work"/capture/*.avi | head -1)

# Seconds into the video for each phase, from the log (its first line is
# written as FDDBench starts, when the capture starts)
read -r w0 w1 b0 b1 < <(python3 - "$work/c/FDDBENCH.LOG" <<'EOF'
import sys
def secs(line):
    h, m, s = line[:11].split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)
lines = [l.strip() for l in open(sys.argv[1], errors="replace") if l[:2].isdigit()]
t0 = secs(lines[0])
def at(text):
    return next(secs(l) - t0 for l in lines if text in l)
print(at("Write and verify: start"), at("Write and verify: Done"),
      at("Benchmark: start"), at("Benchmark: Benchmark results"))
EOF
)
echo "write and verify ${w0}-${w1} s, benchmark ${b0}-${b1} s"

# Normal speed, then write and verify at 3x, normal, the benchmark at 6x, normal.
# VGA text is captured at 720x400 but shown at 4:3.
filter="[0:v]split=5[a][b][c][d][e];
[a]trim=0:$w0,setpts=PTS-STARTPTS[s1];
[b]trim=$w0:$w1,setpts=(PTS-STARTPTS)/3[s2];
[c]trim=$w1:$b0,setpts=PTS-STARTPTS[s3];
[d]trim=$b0:$b1,setpts=(PTS-STARTPTS)/6[s4];
[e]trim=$b1,setpts=PTS-STARTPTS[s5];
[s1][s2][s3][s4][s5]concat=n=5:v=1:a=0,scale=960:720:flags=neighbor[v]"
ffmpeg -v error -y -i "$avi" -filter_complex "$filter" -map "[v]" -an \
  -c:v libx264 -preset slow -crf 18 -tune animation -pix_fmt yuv420p -movflags +faststart \
  docs/fddbench-demo.mp4
ffmpeg -v error -y -i docs/fddbench-demo.mp4 \
  -vf "fps=8,scale=720:540:flags=neighbor,split[a][b];[a]palettegen=max_colors=32:stats_mode=full[p];[b][p]paletteuse=dither=none" \
  docs/fddbench-demo.gif
ls -lh docs/fddbench-demo.*
