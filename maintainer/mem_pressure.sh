#!/bin/sh
# Memory-pressure smoothness test (the user's "many apps open, then fast switching starts to lag" case). heavy_mix.sh
# always starts clean, so it never builds memory pressure; this test does:
#   1. clean start (force-stop every app in recents),
#   2. fill memory: open each app of APPS once (wait WARM s, one fling),
#   3. FrameTimeline trace (jank.cfg) while all apps are opened again in turn, ROUNDS times, OPEN s apart, HOME between,
#   4. report: SF frames by jank type, launcher frames > 120 ms, long D-state waits (> 150 ms, all processes; I/O and
#      reclaim stalls), and the deltas of pgmajfault (file pages read back from flash), pswpin/pswpout (zram), allocstall.
# Screen on, unlocked, landscape. Apps are started with `am start` of their launcher activity (no icon animation).
#   ADB="adb -s 83836a90" sh maintainer/mem_pressure.sh <label>
# Trace: ~/Documents/pipa/port-work/traces/mem-<label>.pftrace. persist.traced.enable is set back to 0.
set -eu
L=${1:?label}
ADB=${ADB:-adb -s 83836a90}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HOME/Documents/pipa/port-work/traces/mem-$L.pftrace
APPS=${APPS:-"app.morphe.android.youtube com.opera.browser com.spotify.music com.android.vending com.coloros.gallery3d tw.nekomimi.nekogram com.android.settings com.android.mms com.android.contacts com.coloros.calculator com.coloros.alarmclock com.coloros.weather2"}
WARM=${WARM:-4}; OPEN=${OPEN:-1.5}; ROUNDS=${ROUNDS:-2}
sh_() { $ADB shell "$1" </dev/null; }
sh_ 'dumpsys window' | grep -q 'isKeyguardShowing=false' || { echo "tablet is locked or asleep: unlock it first"; exit 1; }

# activity of each app (skip apps that are not installed)
ACTS=""
for p in $APPS; do
    a=$(sh_ "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $p 2>/dev/null" | tail -1 | tr -d '\r')
    case $a in */*) [ "${a%%/*}" = "$p" ] && ACTS="$ACTS $a" ;; esac
done
echo "apps: $(echo $ACTS | wc -w)"

echo "== clean start"
sh_ 'for p in $(dumpsys activity recents | grep -oE "realActivity=\{[^/]+" | cut -d"{" -f2 | sort -u); do
    case $p in com.android.launcher|com.android.systemui) ;; *) am force-stop $p ;; esac; done; input keyevent KEYCODE_HOME'
sleep 3

echo "== fill memory"
for a in $ACTS; do
    sh_ "am start -n $a >/dev/null 2>&1; sleep $WARM; input swipe 1440 1300 1440 500 150; sleep 1; input keyevent KEYCODE_HOME"
done
sleep 3

vm() { sh_ "grep -E '^(pgmajfault|pswpin|pswpout|allocstall_normal|allocstall_movable) ' /proc/vmstat" | awk '{printf "%s=%s ", $1, $2}'; }
V0=$(vm)
$ADB push "$HERE/perfetto/jank.cfg" /data/local/tmp/jank.cfg >/dev/null
sh_ "su -c 'setprop persist.traced.enable 1; sleep 2; rm -f /data/misc/perfetto-traces/mem.pftrace; cat /data/local/tmp/jank.cfg | perfetto --txt -c - -o /data/misc/perfetto-traces/mem.pftrace --background' >/dev/null"
sleep 2
echo "== switching ($ROUNDS rounds)"
r=0
while [ $r -lt "$ROUNDS" ]; do
    for a in $ACTS; do sh_ "am start -n $a >/dev/null 2>&1; sleep $OPEN; input keyevent KEYCODE_HOME; sleep 0.6"; done
    r=$((r + 1))
done
sh_ "su -c 'P=\$(pidof perfetto); [ -n \"\$P\" ] && kill -TERM \$P; sleep 4; setprop persist.traced.enable 0'"
V1=$(vm)
sh_ "su -c 'cat /data/misc/perfetto-traces/mem.pftrace; rm -f /data/misc/perfetto-traces/mem.pftrace'" > "$OUT"
sh_ 'input keyevent KEYCODE_MEDIA_PAUSE' || true
echo "vmstat before: $V0"
echo "vmstat after:  $V1"
"$HOME/Documents/pipa/port-work/perfetto-venv/bin/python" -I "$HERE/perfetto/frame_summary.py" "$OUT" 2>&1 | grep -v -iE 'warn|loading' | grep -E 'SF frames' || true
"$HOME/Documents/pipa/port-work/perfetto-venv/bin/python" -I - "$OUT" <<'PY' 2>&1 | grep -v -iE 'warn|loading'
import sys
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace=sys.argv[1]); q = lambda s: list(tp.query(s))
n = q("select count(*) n from actual_frame_timeline_slice a join process p using(upid) where p.name='com.android.launcher' and a.dur>120e6")[0].n
d = q("""select count(*) n, coalesce(sum(ts.dur),0)/1e6 ms from thread_state ts join thread t using(utid) left join process p using(upid)
   where ts.state='D' and ts.dur>150e6 and coalesce(p.name,'') not like 'crtc%'""")[0]
print(f"launcher frames >120 ms: {n}; long D waits (>150 ms): {d.n}, {d.ms:.0f} ms total")
PY
