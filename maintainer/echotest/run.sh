#!/bin/bash
# Run one echo test on the tablet and pull the result (BUGS-TODO 27).
#   bash run.sh <tag> [am extras...]      e.g. bash run.sh vc --ei src 7     bash run.sh mic --ei src 1
# Then: python3 analyse.py out/results
# The tablet must be unlocked with the screen on (the app records in the foreground).
set -eu
cd "$(dirname "$0")"
ADB=(adb -s "${SERIAL:-83836a90}")
tag=$1; shift
dir=/sdcard/Android/data/pipa.echotest/files
mkdir -p out/results
"${ADB[@]}" shell "rm -f $dir/$tag.txt $dir/$tag.raw"
"${ADB[@]}" logcat -c
"${ADB[@]}" shell am start -n pipa.echotest/.Main --es tag "$tag" "$@" >/dev/null
for _ in $(seq 1 30); do
    sleep 1
    "${ADB[@]}" shell "[ -f $dir/$tag.txt ]" && break
done
"${ADB[@]}" pull "$dir/$tag.txt" "$dir/$tag.raw" "$dir/play.raw" out/results/ >/dev/null
"${ADB[@]}" logcat -d > "out/results/$tag.log"
tr '\n' ' ' < "out/results/$tag.txt"; echo
grep -h -o -E "enable_snd_device: snd_device\([0-9]+: [^)]*\)(\[[A-Z_0-9]*\])?|platform_set_echo_reference: enabling [a-z -]*|changing use case [a-z-]* (input|output) device from[^)]*\) to \([0-9]+: [a-z-]*" \
    "out/results/$tag.log" | sort -u
