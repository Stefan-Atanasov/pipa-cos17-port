#!/bin/sh
# funcheck.sh <label>: the same small functional checks on every build (BUGS 141): camera open + its error messages,
# backlight for fixed brightness values, battery/charging, sensors list, audio output devices. Read-only except: it
# opens the camera app, presses Home, and sets brightness for some seconds (restored at the end).
#   ADB="adb -s <serial>" sh maintainer/fromstock/funcheck.sh <label>    -> <root>/port-work/snapshots/<label>/func.txt
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=${PIPA_ROOT:-$(cd "$HERE/../../.." && pwd)}
L=${1:?label}; O=$ROOT/port-work/snapshots/$L; mkdir -p "$O"; F=$O/func.txt
ADB=${ADB:-adb -s ${SERIAL:-83836a90}}
a() { $ADB shell "$@" < /dev/null 2>/dev/null | tr -d '\r'; }
{
a logcat -c
act=$(a cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.oppocamera | tail -1)
a am start -n "$act" > /dev/null; sleep 7
echo "camera client: $(a dumpsys media.camera | grep -o 'Camera ID: [0-9]*, Cost: [0-9]*' | head -1)"
a logcat -d | awk '$5=="E" || $5=="F" {$1=$2=$3=$4=""; print}' | grep -E 'CamX|CHI|Camera|camera' | sed -E 's/^ +//; s/[0-9]+/N/g; s/0xN?[0-9a-f]*/H/g' | sort | uniq -c | sort -rn | head -40 | sed 's/^/camera-err /'
a input keyevent KEYCODE_HOME; sleep 1
m=$(a settings get system screen_brightness_mode); b=$(a settings get system screen_brightness)
a settings put system screen_brightness_mode 0
for v in 10 50 128 255 900 2047; do a settings put system screen_brightness $v; sleep 1.5; echo "brightness $v -> $(a su -c 'cat /sys/class/backlight/panel0-backlight/brightness')"; done
a settings put system screen_brightness "$b"; a settings put system screen_brightness_mode "$m"
echo "battery: $(a dumpsys battery | grep -E 'powered|status|health|level|temperature' | tr -s ' ' | tr '\n' ' ')"
echo "sensors: $(a dumpsys sensorservice | sed -n '/^Sensor List:/,/^$/p' | grep -E '^0x' | sed -E 's/^0x[0-9a-f]+\) //; s/ *\|.*//' | sort | tr '\n' ';' | md5sum | cut -c1-12) (md5 of the names in the Sensor List section)"
echo "audio outputs: $(a dumpsys media.audio_policy | grep -E '^ *- Output' | wc -l)"
} > "$F"
echo "func $L: $(grep -c . "$F") lines in $F"
