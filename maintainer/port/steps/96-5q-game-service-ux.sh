#!/bin/sh
# Phase 5q: OPPO game service UI First marks (ux_task_app ioctl), 2026-11-05, beta7.
#
# * rules_5q_system_ext.cil: allow + allowx 0x2700-0x2701 on oplus_ux_task_app_proc for oplus_game_service (the set of
#   5i). Seen on the pt54 boot (ioctl 0x2701 denied). secilc exit 0, neverallow 76.
#NEEDS: "$HERE/sepolicy/rules_5q_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=5q

SE=$T/system_ext
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 5q" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_5q_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 5q" "$SE/etc/selinux/$f"
    echo "edited  system_ext/etc/selinux/$f"
done

set_layer "$STEP"
