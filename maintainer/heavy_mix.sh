#!/bin/sh
# Heavy mixed smoothness test (the user's "smooth everywhere, fast" case): Spotify plays (Dynamic Island / live alert
# up), then app after app fast: tap an app icon on the home screen (launcher open animation), fling its content
# (3 down, 1 up), HOME (close animation), next app; after each round: shade, Quick Settings, hold the Spotify pill
# (opens Spotify), tap it (expands the live alert card), app drawer (open, fling). Ends with fast open/close bursts of all apps (BURST s open,
# 0.25), then the same with no gap after HOME (next open overlaps the close animation).
# Run from the PC, screen on and unlocked, landscape (2880x1800).
#   ADB="adb -s 83836a90" sh maintainer/heavy_mix.sh <label> [cycles]      (default 16 cycles; NOCLEAN=1: no clean start)
# Timing knobs (s): OPEN (wait after icon tap, 0.6), FL (gap between flings, 0.35), GAP (0.3). Taps and swipes go
# through the touchscreen's kernel input device (maintainer/kgest, root) like a finger; INJECT=1 uses `input` instead.
# Reports gfxinfo (frames janky% p50 p90 p99 slowUI slowDraw) of launcher, SystemUI and the sum of the apps.
# POWER=1: pause charging (battery input_suspend) during the timed part and sample battery current x voltage every
# second on the tablet; prints the average watts (screen on, same brightness for every run). Charging resumes at the end.
# Appends one row to ~/Documents/pipa/port-work/perf-ab/heavy.csv.
ADB=${ADB:-adb -s 83836a90}
L=${1:?label}; N=${2:-16}
ICONS=${ICONS:-"Settings|Photos|YouTube|Opera|Play Store"}   # "|"-separated labels (text or content-desc; dock too)
PKGS=${PKGS:-"com.oplus.wirelesssettings com.coloros.gallery3d app.morphe.android.youtube com.opera.browser com.android.vending com.spotify.music"}
OPEN=${OPEN:-0.6}; FL=${FL:-0.35}; GAP=${GAP:-0.3}
sh_() { $ADB shell "$*" | tr -d '\r'; }

if [ "${INJECT:-0}" = 1 ]; then
	tap() { sh_ "input tap $1 $2"; }; swipe() { sh_ "input swipe $*"; }
else
	$ADB push "$(dirname "$0")/kgest/kgest" /data/local/tmp/kgest >/dev/null; sh_ 'chmod 755 /data/local/tmp/kgest'
	tap() { sh_ "su -c '/data/local/tmp/kgest tap $1 $2'"; }; swipe() { sh_ "su -c '/data/local/tmp/kgest swipe $*'"; }
fi
# clean start: close every app in recents (force-stop, Spotify included), so each run starts from the same state.
# NOCLEAN=1 keeps the open apps (memory-pressure runs after maintainer/mem_fill.sh).
[ "${NOCLEAN:-0}" = 1 ] || sh_ 'input keyevent 3; for p in $(dumpsys activity recents | grep -oE "realActivity=\{[^/]+" | cut -d{ -f2 | sort -u); do
	case $p in com.android.launcher|com.android.systemui|app.revanced.android.gms) ;; *) am force-stop $p ;; esac; done'
# (app.revanced.android.gms = microG, YouTube Morphe needs it running)
sleep 2
sh_ 'monkey -p com.spotify.music -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1'; sleep 4
sh_ 'dumpsys media_session | grep -q "state=PLAYING" || input keyevent 126'; sleep 2
sh_ 'input keyevent 3'; sleep 2
find_xy() {   # icon centres by label; the dock's recent-apps section shifts the dock icons, so re-read every round
	sh_ 'uiautomator dump /data/local/tmp/stress_ui.xml >/dev/null 2>&1'
	XY=$($ADB exec-out cat /data/local/tmp/stress_ui.xml | python3 -I -c '
import re, sys
want = sys.argv[1].split("|"); x = sys.stdin.read(); pos = {}
for m in re.finditer(r"<node [^>]*?text=\"([^\"]*)\"[^>]*?content-desc=\"([^\"]*)\"[^>]*?bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", x):
    t, cd, a, b, c, d = m.groups(); t = t or cd
    if t in want and t not in pos: pos[t] = "%d,%d" % ((int(a) + int(c)) // 2, (int(b) + int(d)) // 2)
print(" ".join(pos[w] for w in want if w in pos))' "$ICONS")
	[ -n "$XY" ] || { echo "no icons found on the home screen"; exit 1; }
}
find_xy; echo "icons: $XY"
for p in com.android.launcher com.android.systemui $PKGS; do sh_ "dumpsys gfxinfo $p reset >/dev/null"; done

if [ "${POWER:-0}" = 1 ]; then
	trap 'sh_ "su -c \"echo 0 > /sys/class/power_supply/battery/input_suspend\""; exit 1' INT TERM
	sh_ "su -c 'B=/sys/class/power_supply/battery; echo 1 > \$B/input_suspend; rm -f /data/local/tmp/pw.txt;
		nohup sh -c \"while :; do echo \\\$(cat \$B/current_now) \\\$(cat \$B/voltage_now) >> /data/local/tmp/pw.txt; sleep 1; done\" >/dev/null 2>&1 &
		echo \$! > /data/local/tmp/pw.pid'"
fi
i=0; t0=$(date +%s)
while [ $i -lt "$N" ]; do
	[ $i -gt 0 ] && find_xy
	for xy in $XY; do                      # app after app: open, fling, home, next
		[ $i -ge "$N" ] && break
		tap ${xy%,*} ${xy#*,}
		sleep "$OPEN"
		swipe 1440 1500 1440 300 120; sleep "$FL"
		swipe 1440 1500 1440 300 120; sleep "$FL"
		swipe 1440 1500 1440 300 120; sleep "$FL"
		swipe 1440 300 1440 1500 120; sleep "$FL"
		sh_ 'input keyevent 3'; sleep "$GAP"
		i=$((i + 1))
	done
	swipe 700 5 700 1100 200; sleep "$GAP"          # once per round: shade, then Quick Settings
	swipe 1440 1500 1440 300 150; sleep "$GAP"
	swipe 2300 5 2300 1100 200; sleep "$GAP"
	swipe 1000 1500 1000 300 150; sleep "$GAP"
	sh_ 'dumpsys window | grep -q "mCurrentFocus.*NotificationShade" && input keyevent 4'
	swipe 1440 46 1440 46 600; sleep "$OPEN"        # Spotify live alert pill: hold = opens Spotify, back
	sh_ 'input keyevent 4'; sleep "$GAP"
	tap 1440 46; sleep "$OPEN"                       # tap the pill = expands the live alert card (SeedlingCard)
	sh_ 'input keyevent 4; input keyevent 3'; sleep "$GAP"
	swipe 1440 1300 1440 400 200; sleep "$OPEN"      # app drawer: swipe up from home, fling down twice and back up
	swipe 1440 1500 1440 300 120; sleep "$FL"
	swipe 1440 1500 1440 300 120; sleep "$FL"
	swipe 1440 300 1440 1500 120; sleep "$FL"
	swipe 1440 300 1440 1500 120; sleep "$FL"
	sh_ 'input keyevent 3'; sleep "$GAP"
done
find_xy                                          # finish: fast open/close bursts, run on the tablet (no adb round trip)
# A home swipe in the bursts sometimes lands in Recents; an icon at the bottom centre (Play Store in the dock, x 1439)
# then hits Recents' "clear all" button and kills every app before gfxinfo is read (INVALID with 0 frames). Skip those.
XY=$(for xy in $XY; do x=${xy%,*}; y=${xy#*,}; [ $y -gt 1500 ] && [ $x -gt 1290 ] && [ $x -lt 1590 ] || printf '%s ' $xy; done)
# HOME = gesture-nav swipe up from the bottom edge through the touchscreen (kgest), like a finger. Round 1-2: open, BURST
# s, home, 0.15 s; round 3-4 (overlap): the next icon is tapped right after the home swipe, while the close animation runs.
sh_ "su -c 'K=/data/local/tmp/kgest; for r in 1 2; do for xy in $XY; do \$K tap \${xy%,*} \${xy#*,}; sleep ${BURST:-0.25};
	\$K swipe 1440 1795 1440 1000 120; sleep 0.15; done; done
	for r in 1 2; do for xy in $XY; do \$K tap \${xy%,*} \${xy#*,}; sleep ${BURST:-0.25}; \$K swipe 1440 1795 1440 1000 120; done; done'"
secs=$(( $(date +%s) - t0 ))
watts=-
if [ "${POWER:-0}" = 1 ]; then
	watts=$(sh_ "su -c 'kill \$(cat /data/local/tmp/pw.pid); echo 0 > /sys/class/power_supply/battery/input_suspend; cat /data/local/tmp/pw.txt'" |
		awk '$1 > 0 {w += $1 * $2 / 1e12; n++} END {if (n) printf "%.2f", w / n; else print "-"}')
fi
playing=$(sh_ 'dumpsys media_session | grep -c "state=PLAYING"')

raw() {   # $1 package -> "frames janky p50 p90 p99 slowui slowdraw" (janky = count)
	sh_ "dumpsys gfxinfo $1" | awk '
	/Total frames rendered/ {f=$4} /Janky frames:/ {j=$3}
	/^50th percentile/ {p50=$3} /^90th percentile/ {p90=$3} /^99th percentile/ {p99=$3}
	/Number Slow UI thread/ {su=$5} /Number Slow issue draw commands/ {sd=$6}
	END {gsub(/ms/,"",p50); gsub(/ms/,"",p90); gsub(/ms/,"",p99); printf "%d %d %s %s %s %d %d", f, j, p50, p90, p99, su, sd}'
}
pct() { echo "$1" | awk '{printf "%s %.1f %s %s %s %s %s", $1, ($1 ? 100*$2/$1 : 0), $3, $4, $5, $6, $7}'; }
la=$(pct "$(raw com.android.launcher)"); ui=$(pct "$(raw com.android.systemui)")
apps=$(for p in $PKGS; do raw $p; echo; done | awk 'NF {f+=$1; j+=$2; su+=$6; sd+=$7; if ($5+0 > p99) p99=$5+0}
	END {printf "%d %.1f - - %d %d %d", f, (f ? 100*j/f : 0), p99, su, sd}')
echo "label=$L cycles=$N in ${secs}s music_playing=$playing avg_power_W=$watts"
echo "launcher  frames janky% p50 p90 p99 slowUI slowDraw: $la"
echo "systemui  frames janky% p50 p90 p99 slowUI slowDraw: $ui"
echo "apps      frames janky% - - maxp99 slowUI slowDraw: $apps"
few=$(for p in $PKGS; do [ $p = com.spotify.music ] && continue; n=$(raw $p | awk '{print $1}'); [ "${n:-0}" -lt 50 ] && printf "%s(%s) " "${p##*.}" "${n:-0}"; done)
[ -n "$few" ] || [ "$playing" = 0 ] && echo "INVALID: apps that hardly opened: ${few:-none}; music_playing=$playing (a floating window or dialog may block the taps)"
PA=${PIPA_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/port-work/perf-ab
mkdir -p "$PA"
echo "$(date +%F_%T),$L,$N,$playing,$secs,$(echo $la | tr ' ' ','),$(echo $ui | tr ' ' ','),$(echo $apps | tr ' ' ','),$watts" >> "$PA/heavy.csv"
