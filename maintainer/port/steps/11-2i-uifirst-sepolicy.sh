#!/bin/sh
# Phase 2i: SELinux labels and rules for OPPO's UI First proc nodes, on top of 2h (system_ext only).
#
# Our WALT kernel (branch oppo) provides ColorOS 17's UI First interface: /proc/oplus_scheduler/sched_assist/
# {ux_task,ux_task_app,im_flag,im_flag_app}, /proc/oplus_frame_boost/sys_ctrl, /proc/sys/fbg/*. Their labels and
# rules are in OPPO's vendor policy, which we do not ship (pipa vendor), so system_server and apps get EACCES on
# plain `proc`. uifirst-policy/sa_block.cil (generated from the donor vendor rules, see uifirst-policy/README.md)
# declares the types, labels the nodes and grants the donor's access. Harmless on kernels without these nodes.
#
# Old layer script: build_beta5_2i.sh
#NEEDS: "$HERE/uifirst-policy/sa_block.cil"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext

echo "== SELinux: UI First proc nodes"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    if grep -q 'oplus_scheduler_sched_assist_proc' "$SE/$f"; then echo "$f: already patched"; exit 1; fi
    # in place (cat >>): owner, mode and SELinux label stay
    cat "$HERE/uifirst-policy/sa_block.cil" >> "$SE/$f"
    echo "edited  system_ext/$f (+$(wc -l < "$HERE/uifirst-policy/sa_block.cil") lines)"
done

