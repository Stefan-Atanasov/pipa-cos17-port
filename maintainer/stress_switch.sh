#!/bin/sh
# Rapid app switching with music playing (the user's lag case: open/close apps from the home screen fast while
# Spotify plays and the Dynamic Island shows). Run from the PC, screen on and unlocked, tablet in landscape.
#   ADB="adb -s 83836a90" sh maintainer/stress_switch.sh <label> [cycles]      (default 30 cycles, ~1 min)
# Per cycle: tap an app icon on the home screen (with the launcher's open animation), wait OPEN s (0.5), HOME,
# wait GAP s (0.35). Icon positions are read from the home screen (uiautomator) at the start, by label.
# Reports jank of the launcher and SystemUI (gfxinfo: janky %, p50/p90/p99 frame time, slow UI thread / draw counts).
# Appends one row to ~/Documents/pipa/port-work/perf-ab/stress.csv. No root needed; it force-stops nothing.
# KTAP=1 taps through the touchscreen's kernel input device (maintainer/ktap.sh, needs root) instead of `input tap`,
# so in-kernel touch boosts (E404 uclamp_boost, devfreq_boost) see the taps like a finger; `input tap` bypasses them.
ADB=${ADB:-adb -s 83836a90}
L=${1:?label}; N=${2:-30}
ICONS=${ICONS:-"Settings Spotify Clock Photos Weather Calculator YouTube Opera"}
OPEN=${OPEN:-0.5}; GAP=${GAP:-0.35}
sh_() { $ADB shell "$*" | tr -d '\r'; }

# music on: open Spotify, press play, back home (the island appears)
[ "${KTAP:-0}" = 1 ] && $ADB push "$(dirname "$0")/ktap.sh" /data/local/tmp/ktap.sh >/dev/null
sh_ 'monkey -p com.spotify.music -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1'; sleep 4
sh_ 'dumpsys media_session | grep -q "state=PLAYING" || input keyevent 126'; sleep 2
sh_ 'input keyevent 3'; sleep 2
sh_ 'uiautomator dump /data/local/tmp/stress_ui.xml >/dev/null 2>&1'
XY=$($ADB exec-out cat /data/local/tmp/stress_ui.xml | python3 -I -c '
import re, sys
want = sys.argv[1].split(); x = sys.stdin.read(); pos = {}
for m in re.finditer(r"<node [^>]*?text=\"([^\"]*)\"[^>]*?bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", x):
    t, a, b, c, d = m.groups()
    if t in want and t not in pos: pos[t] = "%d,%d" % ((int(a) + int(c)) // 2, (int(b) + int(d)) // 2)
print(" ".join(pos[w] for w in want if w in pos))' "$ICONS")
[ -n "$XY" ] || { echo "no icons found on the home screen"; exit 1; }
echo "icons: $XY"
sh_ 'dumpsys gfxinfo com.android.launcher reset >/dev/null; dumpsys gfxinfo com.android.systemui reset >/dev/null'

i=0; t0=$(date +%s)
while [ $i -lt "$N" ]; do
	for xy in $XY; do
		[ $i -ge "$N" ] && break
		if [ "${KTAP:-0}" = 1 ]; then sh_ "su -c 'sh /data/local/tmp/ktap.sh ${xy%,*} ${xy#*,}'"; else sh_ "input tap ${xy%,*} ${xy#*,}"; fi
		sleep "$OPEN"
		sh_ 'input keyevent 3'
		sleep "$GAP"
		i=$((i + 1))
	done
done
secs=$(( $(date +%s) - t0 ))
playing=$(sh_ 'dumpsys media_session | grep -c "state=PLAYING"')

stats() {   # $1 package -> "frames janky% p50 p90 p99 slowui slowdraw"
	sh_ "dumpsys gfxinfo $1" | awk '
	/Total frames rendered/ {f=$4} /Janky frames:/ {j=$4; gsub(/[()%]/,"",j)}
	/^50th percentile/ {p50=$3} /^90th percentile/ {p90=$3} /^99th percentile/ {p99=$3}
	/Number Slow UI thread/ {su=$5} /Number Slow issue draw commands/ {sd=$6}
	END {gsub(/ms/,"",p50); gsub(/ms/,"",p90); gsub(/ms/,"",p99); printf "%s %s %s %s %s %s %s", f, j, p50, p90, p99, su, sd}'
}
la=$(stats com.android.launcher); su=$(stats com.android.systemui)
echo "label=$L cycles=$N in ${secs}s music_playing=$playing"
echo "launcher  frames janky% p50 p90 p99 slowUI slowDraw: $la"
echo "systemui  frames janky% p50 p90 p99 slowUI slowDraw: $su"
mkdir -p ~/Documents/pipa/port-work/perf-ab
echo "$(date +%F_%T),$L,$N,$playing,$secs,taps,$(echo $la | tr ' ' ','),$(echo $su | tr ' ' ',')" >> ~/Documents/pipa/port-work/perf-ab/stress.csv
