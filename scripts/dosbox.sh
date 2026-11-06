#!/usr/bin/env bash
# Runs FDDBench in DOSBox-X, with build/disk144.img as A: and build/dos as C:.
#
#   scripts/dosbox.sh run     a window, the menu
#   scripts/dosbox.sh smoke   hidden: /AUTO, then checks the log and the final screen
set -euo pipefail
cd "$(dirname "$0")/.."
dosbox=${DOSBOX_X:-$(command -v dosbox-x)}
mode=${1:-run}
rm -f build/dos/FDDBENCH.LOG build/dos/SCREEN.TXT

if [ "$mode" = run ]; then
  "$dosbox" -fastlaunch -nomenu \
    -c "imgmount a build/disk144.img -t floppy" -c "mount c build/dos" -c "c:" -c "FDDBENCH A:" -c "exit"
  exit
fi

# DOSBox-X here; plain DOSBox in CI (DOSBOX_X=dosbox), which lacks DOSBox-X's options
extra=(-fastlaunch -nomenu -time-limit 300)
case "$(basename "$dosbox")" in dosbox) extra=() ;; esac
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy $(command -v timeout >/dev/null && echo timeout 360) "$dosbox" "${extra[@]}" \
  -c "imgmount a build/disk144.img -t floppy" -c "mount c build/dos" -c "c:" \
  -c "FDDBENCH A: /AUTO /DUMP:SCREEN.TXT" -c "exit" > build/dosbox.log 2>&1 || true

echo "== FDDBENCH.LOG"; cat build/dos/FDDBENCH.LOG
echo "== SCREEN.TXT"; cat build/dos/SCREEN.TXT
fail=0
grep -q "Run all: end" build/dos/FDDBENCH.LOG || { echo "FAIL: the run didn't finish"; fail=1; }
grep -q "Game loading: Done" build/dos/FDDBENCH.LOG || { echo "FAIL: the last scenario didn't finish"; fail=1; }
if grep -E "[1-9][0-9]* errors" build/dos/FDDBENCH.LOG; then echo "FAIL: read errors"; fail=1; fi
grep -q "C75" build/dos/SCREEN.TXT || { echo "FAIL: no map on the final screen"; fail=1; }
[ $fail = 0 ] && echo "smoke: OK"
exit $fail
