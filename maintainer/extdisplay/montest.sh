#!/bin/bash
# Monitor test for BUGS 54 (external display): run with the monitor connected (ADB over Wi-Fi, the monitor uses the
# USB-C port). Shows: modes and their flags (5a: no FLAG_SIZE_OVERRIDE), active mode, the preferred mode, desktop desks.
#   ADB="adb -s <ip>:5555" bash montest.sh [set120]
ADB=${ADB:-adb -s 192.168.0.219:5555}
D=$($ADB shell dumpsys display 2>/dev/null)
ID=$(printf '%s\n' "$D" | grep -oE 'DisplayInfo\{"[^"]+", displayId [0-9]+' | grep -v 'Built-in' | grep -oE '[0-9]+$' | head -1)
NAME=$(printf '%s\n' "$D" | grep -oE 'DisplayInfo\{"[^"]+", displayId '"$ID" | head -1 | cut -d'"' -f2)
[ -n "$ID" ] || { echo "no external display"; exit 1; }
echo "external display: $NAME id=$ID"
printf '%s\n' "$D" | grep -m1 "DisplayDeviceInfo{\"$NAME\"" | grep -oE '\{id=[0-9]+[^}]*fps=[0-9.]+' | sed 's/, parentModeId=-1, sfModeId=[0-9]*//' | head -8
echo "size-override modes: $(printf '%s\n' "$D" | grep -m1 "DisplayDeviceInfo{\"$NAME\"" | grep -o FLAG_SIZE_OVERRIDE | wc -l) (5a: expect 0)"
if [ "$1" = set120 ]; then
    W=$(printf '%s\n' "$D" | grep -m1 "DisplayDeviceInfo{\"$NAME\"" | grep -oE '"[^"]+": uniqueId="[^"]+", [0-9]+ x [0-9]+' | grep -oE '[0-9]+ x [0-9]+' | tr -d ' ' | tr x ' ')
    set -- $W
    RATE=$(printf '%s\n' "$D" | grep -m1 "DisplayDeviceInfo{\"$NAME\"" | grep -oE "width=$1, height=$2, fps=[0-9.]+" | grep -oE '[0-9.]+$' | sort -g | tail -1)
    echo "set preferred: $1x$2@$RATE"; $ADB shell cmd display set-user-preferred-display-mode "$1" "$2" "$RATE" "$ID"; sleep 4
fi
$ADB shell "dumpsys SurfaceFlinger --displays 2>/dev/null" | grep -A4 "name=\"$NAME\"" | grep -oE 'activeMode=\{[^}]*\}' | head -1
$ADB shell cmd display get-user-preferred-display-mode "$ID"
echo "desks / modes on display $ID:"; $ADB shell "dumpsys activity activities 2>/dev/null" | awk -v d="Display #$ID " 'index($0,d)==1{f=1;next} /^Display #/{f=0} f && /\* Task\{/' | cut -c1-150 | head -8
