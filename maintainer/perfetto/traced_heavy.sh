#!/bin/sh
# One heavy_mix run (10 cycles, OPEN=0.4 FL=0.2 GAP=0.2) under a perfetto FrameTimeline trace (jank.cfg), then the
# summary that matters for visible stutter: SF frames by jank type, launcher Buffer Stuffing / App Deadline, long
# DRM commits. Screen on, unlocked, landscape; hands off.
#   ADB="adb -s 83836a90" sh maintainer/perfetto/traced_heavy.sh <label>
# Trace: ~/Documents/pipa/port-work/traces/<label>.pftrace (~400 MB). persist.traced.enable is set back to 0.
set -eu
L=${1:?label}
ADB=${ADB:-adb -s 83836a90}
HERE=$(cd "$(dirname "$0")" && pwd)
PW=${PIPA_ROOT:-$(cd "$HERE/../../.." && pwd)}/port-work
OUT=$PW/traces/$L.pftrace
$ADB shell dumpsys window | grep -q 'isKeyguardShowing=false' || { echo "tablet is locked or asleep: unlock it first"; exit 1; }
$ADB push "$HERE/jank.cfg" /data/local/tmp/jank.cfg >/dev/null
$ADB shell "su -c 'setprop persist.traced.enable 1; sleep 2; rm -f /data/misc/perfetto-traces/ab.pftrace; cat /data/local/tmp/jank.cfg | perfetto --txt -c - -o /data/misc/perfetto-traces/ab.pftrace --background' >/dev/null"
sleep 2
ADB="$ADB" OPEN=0.4 FL=0.2 GAP=0.2 sh "$HERE/../heavy_mix.sh" "$L" 10 2>&1 | grep -E '^(launcher|systemui) '
$ADB shell "su -c 'kill -TERM \$(pidof perfetto); sleep 4; setprop persist.traced.enable 0'"
$ADB shell "su -c 'cat /data/misc/perfetto-traces/ab.pftrace; rm -f /data/misc/perfetto-traces/ab.pftrace'" > "$OUT"
"$PW/perfetto-venv/bin/python" -I "$HERE/frame_summary.py" "$OUT" 2>&1 | grep -v -iE 'warn|loading'
