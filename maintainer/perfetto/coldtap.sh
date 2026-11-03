#!/bin/bash
# Cold starts by real touch (kgest tap on home-screen icons of the pt40 layout, landscape): force-stop, home, tap,
# ActivityTaskManager "Displayed" time. Push maintainer/kgest/kgest to /data/local/tmp first. Coordinates: uiautomator dump.
A="adb -s 83836a90"
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
run Settings 459 1290 com.android.settings
run YouTube 895 1290 com.google.android.youtube
run Photos 1549 1290 com.coloros.gallery3d com.google.android.apps.photos
run PlayStore 677 1290 com.android.vending
run AppMarket 1767 1290 com.heytap.market
run Spotify 2203 1290 com.spotify.music
