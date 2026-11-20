#!/bin/sh
# Phase 8p (2026-11-20, BUGS B1 "Wi-Fi sometimes does not turn on"): event-driven log capture, no idle cost.
# * port-rom/pipa_port.rc: init property triggers start the oneshot service pipa_b1_cap (domain pipa_port):
#   sys.oplus.wifi.coldreset=1 (ColorOS asks for a cold reset after a failed Wi-Fi switch), sys.oplus.wifi.trace=1
#   (ColorOS "framework stuck"), Wi-Fi HAL / wificond restarting, and sys.pipa.b1capture=<any new value> by hand.
# * port-rom/pipa_port/b1_capture.sh: props, dmesg and a logcat Wi-Fi slice into /data/misc/pipa_port/b1-*.txt; once per
#   10 min, newest 5 kept. Design: port-work/codex/b1-capture-20261120/REPORT.md (Sonnet, checked).
# * maintainer/sepolicy/rules_8p_system_ext.cil: logcat (read_logd), dmesg (syslog_read), wifi_hal_prop, sysfs_net.
#   Denials from a runcon test on pt143; on-device secilc compile OK, neverallow count 76 = donor base.
# Both files come with the pipa_port folder and rc (step 2e copies them).
set -eu
. "$PORT/lib.sh"
STEP=8p
SE=$T/system_ext
need_grep 'pipa_b1_cap' "$SE/etc/init/pipa_port.rc"
[ -f "$SE/pipa_port/b1_capture.sh" ] || die "no b1_capture.sh in system_ext/pipa_port"
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 8p" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_8p_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 8p" "$SE/etc/selinux/$f"
done
echo "system_ext sepolicy: B1 capture rules (8p)"
set_layer "$STEP"
