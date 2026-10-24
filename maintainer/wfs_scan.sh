#!/bin/bash
# Find native libraries where a new donor build added a blocking waitForService that the old build did not have.
# A waitForService on a vendor HAL pipa lacks hangs system_server until its watchdog panics the device (beta5,
# 2026-10-22: libupdateprof.qti.so, libtrigger-handler.so; module/README.md section 15). Run before flashing a rebase.
#
#   sudo bash wfs_scan.sh <old tree> <new tree>     e.g.  ../reference/cos17  ~/Documents/pipa/port-work/beta5/tree
#
# Trees are extracted partition roots containing system/, system_ext/, product/. Read-only.
set -u
OLD=${1:?usage: wfs_scan.sh <old tree> <new tree>}; NEW=${2:?usage: wfs_scan.sh <old tree> <new tree>}
cd "$NEW"
find system system_ext product -name '*.so' -type f 2>/dev/null | while read -r f; do
    [ -f "$OLD/$f" ] || continue
    cmp -s "$f" "$OLD/$f" && continue
    n_new=$(strings -n 8 "$f" | grep -cE 'waitForService|waitForDeclaredService')
    n_old=$(strings -n 8 "$OLD/$f" | grep -cE 'waitForService|waitForDeclaredService')
    [ "$n_new" -gt "$n_old" ] && echo "$f  (old $n_old -> new $n_new)"
done
echo "(also check new Java waitForService calls in changed framework jars; the IEngineer one sits in oplus-services.jar)"
