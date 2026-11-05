#!/bin/sh
# Phase 5p: OPPO game optimizer for games that target SDK 34; Play services frame boost (2026-11-05, beta7).
#
# * rules_5p_system_ext.cil: the donor policy (ossi_generic untrusted_app_32.te) lets apps of untrusted_app_25..32 and
#   untrusted_app reach oiface (socket, services, its /proc reads and setsched) and horae, but has no copy for
#   untrusted_app_34: Delta Force got "connectto oiface" denied. 8 copies of the _32 rules (game part only; not payjoy,
#   urcc, Qualcomm HAL memfds). gmscore_app gets the frame boost set of 5i. secilc exit 0, neverallow 76.
#NEEDS: "$HERE/sepolicy/rules_5p_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=5p

SE=$T/system_ext
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 5p" "$SE/etc/selinux/$f"
    need_grep "(allow untrusted_app_32 oiface (unix_stream_socket (connectto)))" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_5p_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 5p" "$SE/etc/selinux/$f"
    echo "edited  system_ext/etc/selinux/$f"
done

set_layer "$STEP"
