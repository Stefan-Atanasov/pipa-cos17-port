#!/bin/sh
# Step 9b (2026-11-25, BUGS 183): Collect logs adds the kernel log of the previous boot (pstore ramoops), so a
# spontaneous restart can be read from a tester's bundle without a su command.
# The pipa_port domain may not read pstorefs (platform neverallow for coredomain), but init may: pipa_port.rc copies
# /sys/fs/pstore/console-ramoops-0 (and dmesg-ramoops-0 after a panic) to /data/misc/pipa_logs at post-fs-data (old
# copies removed first); collect_logs.sh puts them through redact.sed into the bundle. One rule: init may write
# pipa_logs_file (maintainer/sepolicy/rules_9b_system_ext.cil). On-device secilc 2026-11-25: exit 0, neverallow
# failures 76 = donor base.
# pipa_port.rc and collect_logs.sh come with the earlier copy step (2e); this step checks them and adds the rule.
#NEEDS: "$HERE/sepolicy/rules_9b_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=9b
SE=$T/system_ext
RC=$SE/etc/init/pipa_port.rc
[ -f "$RC" ] || die "no $RC"
need_grep 'copy /sys/fs/pstore/console-ramoops-0 /data/misc/pipa_logs/pstore-console-ramoops-0.txt' "$RC"
need_grep 'pstore-\*.txt' "$SE/pipa_port/collect_logs.sh"
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 9b" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_9b_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 9b" "$SE/etc/selinux/$f"
done
echo "pstore copy (pipa_port.rc), collect_logs.sh and the init rule in place"
set_layer "$STEP"
