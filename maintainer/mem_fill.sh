#!/bin/sh
# Fill memory like real use before a smoothness run: clean start, then open each app of APPS once (`am start`, WARM s,
# one fling, HOME). Then run the smoothness test without its clean start, e.g.
#   ADB="adb -s 83836a90" sh maintainer/mem_fill.sh && NOCLEAN=1 ADB="adb -s 83836a90" sh maintainer/perfetto/traced_heavy.sh <label>
set -eu
ADB=${ADB:-adb -s 83836a90}
APPS=${APPS:-"app.morphe.android.youtube com.opera.browser com.android.vending com.coloros.gallery3d tw.nekomimi.nekogram com.android.settings com.android.mms com.android.contacts com.coloros.calculator com.coloros.alarmclock com.coloros.weather2 com.spotify.music"}
WARM=${WARM:-4}
sh_() { $ADB shell "$1" </dev/null; }
sh_ 'input keyevent 3; for p in $(dumpsys activity recents | grep -oE "realActivity=\{[^/]+" | cut -d{ -f2 | sort -u); do
	case $p in com.android.launcher|com.android.systemui|app.revanced.android.gms) ;; *) am force-stop $p ;; esac; done'
n=0
for p in $APPS; do
    a=$(sh_ "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $p 2>/dev/null" | tail -1 | tr -d '\r')
    case $a in "$p"/*) ;; *) continue ;; esac
    sh_ "am start -n $a >/dev/null 2>&1; sleep $WARM; input swipe 1440 1300 1440 500 150; sleep 1; input keyevent 3"
    n=$((n + 1))
done
sleep 2
echo "filled with $n apps; $(sh_ "grep MemAvailable /proc/meminfo" | awk '{printf "MemAvailable %d MB", $2/1024}')"
