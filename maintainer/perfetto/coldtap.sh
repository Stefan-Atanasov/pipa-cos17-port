#!/bin/bash
# Cold starts by real touch (kgest tap on home-screen icons, landscape): force-stop, home, tap, ActivityTaskManager
# "Displayed" time, 3 runs per app. Push maintainer/kgest/kgest to /data/local/tmp first.
# Icons are found by their label (uiautomator dump of the home screen), so a new home layout needs no change.
# An app whose icon is not on the first home page (e.g. in a folder) prints "not on home".
A=${ADB:-adb -s 83836a90}
$A shell "input keyevent 3"; sleep 1.5
$A shell "uiautomator dump /data/local/tmp/home.xml >/dev/null 2>&1"
XML=$($A shell cat /data/local/tmp/home.xml)
pos() { # label -> "x y" (centre of the node with this text / content-desc)
  printf '%s' "$XML" | python3 -c '
import re,sys
x=sys.stdin.read(); l=sys.argv[1]
for m in re.finditer(r"<node [^>]*>", x):
    n=m.group(0)
    if re.search(r"(text|content-desc)=\"%s\"" % re.escape(l), n):
        b=re.search(r"bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", n)
        if b:
            a,c,d,e=map(int,b.groups()); print((a+d)//2,(c+e)//2); break
' "$1"
}
run() { # label x y pkgs
  l=$1; x=$2; y=$3; shift 3; out=""
  for i in 1 2 3; do
    for p in "$@"; do $A shell "am force-stop $p"; done
    $A shell "input keyevent 3"; sleep 2; $A logcat -c
    $A shell "su -c '/data/local/tmp/kgest tap $x $y'"; sleep 4
    d=$($A logcat -d | grep -E "ActivityTaskManager: Displayed|Fully drawn" | grep -oE "Displayed [^ ]+ for user 0: \+[0-9a-z]+|Displayed [^ ]+: \+[0-9a-z]+" | head -1)
    out="$out | ${d##*+}"; pk="${d#Displayed }"; pk="${pk%%/*}"
  done
  $A shell "input keyevent 3"
  echo "$l ($pk)$out"
}
app() { # label pkgs...
  l=$1; shift; p=$(pos "$l")
  if [ -z "$p" ]; then echo "$l (not on home)"; return; fi
  run "$l" $p "$@"
}
app Settings com.android.settings
app YouTube com.google.android.youtube
app Photos com.coloros.gallery3d com.google.android.apps.photos
app "Play Store" com.android.vending
app "App Market" com.heytap.market
app Spotify com.spotify.music
