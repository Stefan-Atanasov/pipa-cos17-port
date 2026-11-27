#!/bin/sh
# Step 9m (BUGS-TODO 198, user 2026-11-26: "most useful log under ~10 MB"): Collect logs also covers restarts.
# Before: logcat and dmesg live only in RAM (4 MB logd buffers = ~13 min on a busy tablet) and are lost at every
# restart; the previous boot left only the pstore kernel log (warm restarts only).
# * pipa_port/service.sh: one logcat reader (blocking read on logd, no polling, started before boot_completed) keeps
#   priority E and up of main/system/crash plus Watchdog warnings in /data/misc/pipa_logs/err.log (2 MB, 3 rotated
#   copies, ~3 h of errors). It survives restarts. ERR_LOG=0 in /data/misc/pipa_port/config.prop turns it off.
# * pipa_port/collect_logs.sh: adds err.log*; keeps the tar.gz under 10 MB (newest 150000 logcat lines if larger).
# * system/build.prop persist.logd.size 4M -> 8M: logcat in the bundle reaches ~25 min back (RAM only while used).
# Android's dropbox (crash records) is not read: platform neverallow (domain.te: only system_server & co.); the same
# crashes are in err.log. No new SELinux rule (pipa_logs_file rules from 8q). Live test 2026-11-26 on pt167 (bind
# mount): reader in pipa_port, file pipa_logs_file, a service restart replaces the reader; bundle 2.98 MB in 60 s.
# The scripts come with the pipa_port folder (step 2e copies it).
set -eu
. "$PORT/lib.sh"
STEP=9m
echo "== 9m persistent error log + logd 8 MB"

SE=$T/system_ext
need_grep 'pipa_logs/err.log' "$SE/pipa_port/service.sh"
need_grep 'err.log\*' "$SE/pipa_port/collect_logs.sh"
P=$T/system/system/build.prop
[ -f "$P" ] || die "no $P"
need_grep '^persist.logd.size=4M$' "$P"
sed 's/^persist.logd.size=4M$/persist.logd.size=8M/' "$P" > "$R/build.prop.9m"
need_grep '^persist.logd.size=8M$' "$R/build.prop.9m"
cat "$R/build.prop.9m" > "$P"   # in place: owner, mode and SELinux label stay
rm -f "$R/build.prop.9m"
set_layer "$STEP"
