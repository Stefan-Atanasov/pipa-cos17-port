#!/bin/sh
# Step 9o (BUGS-TODO 204, user 2026-11-26): the charging limit (Settings > Battery, 80 % etc.) also holds while the
# screen is off. pipa_port checks the limit in its loop, which runs only while the CPU is awake; screen off the tablet
# sleeps between the fuel gauge's 1 % wake-ups and could charge past the limit (stock OPPO checks in its kernel driver).
# * pipa_port/service.sh chg_hold: in the last 4 % before the limit (charger in, no hold yet) a wake lock "pipa_chg"
#   (30 s timeout, re-armed each check: ends by itself) keeps the check running, ~5-10 min on the charger; released
#   at the hold (the kernel keeps restrict_chg / charging off while asleep) or at unplug. The loop checks every pass
#   while the charger is in (builtin reads), so one 1 % wake-up near the limit is enough.
# * SELinux (maintainer/sepolicy/pipa_port_rules.cil, applied by 2e/3g): pipa_port may write sysfs_wake_lock and has
#   capability2 block_suspend (pt171 had only the file rule: denied); also sys_nice for the 9m logcat reader. On-device secilc: exit 0, neverallow count 76 = donor base.
# Host test 2026-11-26 (chg_hold with fake sysfs files, limit 80): 75 no lock, 76-79 lock, 80 cap + release,
# 81 stop, 79 cap, 77 charge again + lock, unplug: no lock.
# The scripts come with the pipa_port folder (step 2e copies it).
set -eu
. "$PORT/lib.sh"
STEP=9o
echo "== 9o charge limit: wake lock near the limit"

SE=$T/system_ext
need_grep 'awake near the limit' "$SE/pipa_port/service.sh"
need_grep 'pipa_chg 30000000000' "$SE/pipa_port/service.sh"
grep -q 'sysfs_wake_lock' "$SE/etc/selinux/system_ext_sepolicy.cil" || die "pipa_port sysfs_wake_lock rule not in the policy"
grep -q 'block_suspend' "$SE/etc/selinux/system_ext_sepolicy.cil" || die "pipa_port block_suspend rule not in the policy"
set_layer "$STEP"
