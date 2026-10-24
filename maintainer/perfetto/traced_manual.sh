#!/bin/sh
# FrameTimeline trace (jank.cfg) while a person uses the tablet by hand (no scripted gestures), then the same
# summary as traced_heavy.sh: SF frames by jank type, launcher Buffer Stuffing / App Deadline, long DRM commits.
#   ADB="adb -s 83836a90" sh maintainer/perfetto/traced_manual.sh start [seconds]    (default 120; ring buffer)
#   ADB="adb -s 83836a90" sh maintainer/perfetto/traced_manual.sh stop <label>
# Trace: ~/Documents/pipa/port-work/traces/<label>.pftrace. persist.traced.enable is set back to 0 at stop.
set -eu
ADB=${ADB:-adb -s 83836a90}
HERE=$(cd "$(dirname "$0")" && pwd)
case ${1:?start|stop} in
start)
    D=${2:-120}
    $ADB shell dumpsys window | grep -q 'isKeyguardShowing=false' || { echo "tablet is locked or asleep: unlock it first"; exit 1; }
    sed "s/^duration_ms: .*/duration_ms: $((D * 1000))/" "$HERE/jank.cfg" | $ADB shell "cat > /data/local/tmp/jank_manual.cfg"
    $ADB shell "su -c 'setprop persist.traced.enable 1; sleep 2; rm -f /data/misc/perfetto-traces/manual.pftrace; cat /data/local/tmp/jank_manual.cfg | perfetto --txt -c - -o /data/misc/perfetto-traces/manual.pftrace --background' >/dev/null"
    echo "tracing for up to $D s"
    ;;
stop)
    L=${2:?label}
    OUT=$HOME/Documents/pipa/port-work/traces/$L.pftrace
    $ADB shell "su -c 'P=\$(pidof perfetto); [ -n \"\$P\" ] && kill -TERM \$P; sleep 4; setprop persist.traced.enable 0'"
    $ADB shell "su -c 'cat /data/misc/perfetto-traces/manual.pftrace; rm -f /data/misc/perfetto-traces/manual.pftrace'" > "$OUT"
    ls -la "$OUT" | awk '{print $5, $9}'
    "$HOME/Documents/pipa/port-work/perfetto-venv/bin/python" -I "$HERE/frame_summary.py" "$OUT" 2>&1 | grep -v -iE 'warn|loading'
    ;;
esac
