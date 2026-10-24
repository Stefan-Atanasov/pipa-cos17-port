#!/bin/sh
# Shade / Quick Settings pull-down and list scrolling (the user's "smooth everywhere" case). Run from the PC, screen on
# and unlocked, tablet in landscape (2880x1800).
#   ADB="adb -s 83836a90" sh maintainer/shade_scroll.sh <label> [cycles]      (default 15 cycles, ~1.5 min)
# Per cycle: pull the notification shade (top left) and close it, pull Quick Settings (top right) and close it, then in
# Settings fling the main list down and up twice. Swipes use `input swipe` (injected, like ktap's predecessor).
# Reports gfxinfo of SystemUI and Settings: frames janky% p50 p90 p99 slowUI slowDraw.
# Appends one row to ~/Documents/pipa/port-work/perf-ab/shade.csv. No root needed.
ADB=${ADB:-adb -s 83836a90}
L=${1:?label}; N=${2:-15}
SW=${SW:-250}        # swipe duration ms
sh_() { $ADB shell "$*" | tr -d '\r'; }

sh_ 'input keyevent 3'; sleep 1
sh_ 'dumpsys gfxinfo com.android.systemui reset >/dev/null; dumpsys gfxinfo com.android.settings reset >/dev/null'
t0=$(date +%s); i=0
while [ $i -lt "$N" ]; do
	sh_ "input swipe 700 5 700 1100 $SW"; sleep 0.8
	sh_ "input swipe 1440 1500 1440 300 $SW"; sleep 0.8         # close shade by swiping up
	sh_ "input swipe 2300 5 2300 1100 $SW"; sleep 0.8
	sh_ "input swipe 1000 1500 1000 300 $SW"; sleep 0.8         # close QS (swipe up on the left blurred area)
	sh_ 'dumpsys window | grep -q "mCurrentFocus.*NotificationShade" && input keyevent 4'
	i=$((i + 1))
done
sh_ 'am start -W -a android.settings.SETTINGS >/dev/null 2>&1'; sleep 2
i=0
while [ $i -lt "$N" ]; do
	sh_ "input swipe 1800 1500 1800 300 150"; sleep 0.9         # fling down the list
	sh_ "input swipe 1800 1500 1800 300 150"; sleep 0.9
	sh_ "input swipe 1800 300 1800 1500 150"; sleep 0.9         # back up
	sh_ "input swipe 1800 300 1800 1500 150"; sleep 0.9
	i=$((i + 1))
done
sh_ 'input keyevent 3'
secs=$(( $(date +%s) - t0 ))

stats() {   # $1 package -> "frames janky% p50 p90 p99 slowui slowdraw"
	sh_ "dumpsys gfxinfo $1" | awk '
	/Total frames rendered/ {f=$4} /Janky frames:/ {j=$4; gsub(/[()%]/,"",j)}
	/^50th percentile/ {p50=$3} /^90th percentile/ {p90=$3} /^99th percentile/ {p99=$3}
	/Number Slow UI thread/ {su=$5} /Number Slow issue draw commands/ {sd=$6}
	END {gsub(/ms/,"",p50); gsub(/ms/,"",p90); gsub(/ms/,"",p99); printf "%s %s %s %s %s %s %s", f, j, p50, p90, p99, su, sd}'
}
ui=$(stats com.android.systemui); st=$(stats com.android.settings)
echo "label=$L cycles=$N in ${secs}s"
echo "systemui  frames janky% p50 p90 p99 slowUI slowDraw: $ui"
echo "settings  frames janky% p50 p90 p99 slowUI slowDraw: $st"
mkdir -p ~/Documents/pipa/port-work/perf-ab
echo "$(date +%F_%T),$L,$N,$secs,$(echo $ui | tr ' ' ','),$(echo $st | tr ' ' ',')" >> ~/Documents/pipa/port-work/perf-ab/shade.csv
