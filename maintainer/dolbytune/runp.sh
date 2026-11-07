#!/bin/bash
S=$(cd "$(dirname "$0")"; pwd); cd "$S"
ctl() { adb -s 83836a90 shell "CLASSPATH=/data/local/tmp/ctl.dex app_process /system/bin Ctl $*" 2>&1 | grep -v WARN; }
for c in "$@"; do set -- $c; name=$1; shift; adb -s 83836a90 shell input keyevent 224; ctl "$@" >/dev/null; sleep 2
  SWEEP=pink bash rec.sh runs/p-$name.wav; python3 $S/pk.py runs/p-$name.npy runs/p-$name.wav; echo "done $name"; done
