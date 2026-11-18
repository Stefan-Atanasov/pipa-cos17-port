#!/bin/bash
# Audit capture (BUGS 113): pull logs after a clean boot + normal use.
#   bash maintainer/audit_capture.sh <outdir>
# Before the reboot: setprop persist.logd.size 16M (and persist.sys.assert.panic true for app logs). Reset both after.
set -u
OUT=${1:?outdir}; mkdir -p "$OUT"
A() { adb -s "${SERIAL:-83836a90}" "$@"; }
R() { A shell "su -c '$1'"; }
R 'echo $(( $(date +%s) - $(cut -d. -f1 /proc/uptime) ))' > "$OUT/boot_epoch"
R 'logcat -b all -d -v threadtime' > "$OUT/logcat-all.txt"
R 'dmesg' > "$OUT/dmesg.txt"
R 'dumpsys dropbox --print' > "$OUT/dropbox-print.txt" 2>&1
R 'ls -la /data/tombstones /data/anr /data/system/dropbox | tail -n 60' > "$OUT/crash-ls.txt" 2>&1
R 'cat /data/local/tmp/pipa_port.log' > "$OUT/pipa_port.log" 2>&1
R 'for f in /proc/pressure/*; do echo "== $f"; cat $f; done; cat /proc/meminfo | head -8' > "$OUT/pressure.txt"
R 'getprop' > "$OUT/getprop.txt"
wc -l "$OUT"/* | tail -n 12
