#!/bin/sh
# Keep a landscape shooter (PUBG Training Ground) busy for RAM/smoothness tests: run forward (joystick hold) while
# the camera turns (swipe on the right half), in a loop on the tablet. Coordinates: 2880x1800 landscape.
#   sh maintainer/game_move.sh start [seconds]     (default 120; runs on the tablet in the background)
#   sh maintainer/game_move.sh stop
set -eu
ADB=${ADB:-adb -s 83836a90}
case ${1:-start} in
start) S=${2:-120}
  $ADB shell "su -c 'nohup sh -c \"end=\\\$((\\\$(date +%s)+$S)); while [ \\\$(date +%s) -lt \\\$end ]; do
    input swipe 425 1475 425 1250 2600 & input swipe 1900 700 2500 760 2400; wait;
    input swipe 425 1475 520 1260 2600 & input swipe 2500 760 1900 700 2400; wait; done\" > /dev/null 2>&1 &
    echo \$! > /data/local/tmp/game_move.pid'" ;;
stop) $ADB shell "su -c 'kill \$(cat /data/local/tmp/game_move.pid) 2>/dev/null; rm -f /data/local/tmp/game_move.pid'" ;;
esac
