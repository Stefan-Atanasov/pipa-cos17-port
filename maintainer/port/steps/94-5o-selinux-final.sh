#!/bin/sh
# Phase 5o: the last SELinux noise from the pt52 boot and the bug hunt (2026-11-05, beta7).
#
# * rules_5o_system_ext.cil: dontaudit for the OPPO game service lookup of the AOSP virtual device service (game
#   start), the game anti-cheat /proc probes of third-party apps (PUBG, Delta Force; the same kind as 5i/5j) and an
#   OPPO system app search of the Play services data folder. No allow rule. secilc exit 0, neverallow 76.
#NEEDS: "$HERE/sepolicy/rules_5o_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=5o

SE=$T/system_ext
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 5o" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_5o_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 5o" "$SE/etc/selinux/$f"
    echo "edited  system_ext/etc/selinux/$f"
done

set_layer "$STEP"
