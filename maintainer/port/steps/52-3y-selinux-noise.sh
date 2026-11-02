#!/bin/sh
# Phase 3y: SELinux log noise of platform domains (BUGS-TODO 40, public bug doc 2026-11-02).
#
# beta6 logs ~2200 denials in 47 h outside pipa_port: ColorOS apps retry the Qualcomm dpmd tcm socket in a loop,
# system_suspend / system_server / zygote read OPPO props that the HyperOS vendor labels vendor_default_prop, apps
# cannot open the OPPO scheduler hints (/proc/oplus_scheduler/sched_assist, /proc/oplus_frame_boost) that kernel walt
# has. Part of it is Android 17: targetSdk 36 apps run in priv_app_36 / platform_app_36, which the vendor rules for
# priv_app / platform_app do not reach. Rules: sepolicy/noise_rules_system_ext.cil (system_ext CIL and its _debug copy)
# and sepolicy/noise_rules_vendor.cil (vendor-only types). Compiled on the tablet with secilc, the init file set (exit 0).
#NEEDS: "$HERE/sepolicy/noise_rules_system_ext.cil" "$HERE/sepolicy/noise_rules_vendor.cil"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 3y" "$SE/$f"
    cat "$HERE/sepolicy/noise_rules_system_ext.cil" >> "$SE/$f"
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 3y" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 3y" "$CIL"
need_grep "sysfs_zram_202604" "$CIL"
need_grep "^(type vendor_system_prop)" "$CIL"
cat "$HERE/sepolicy/noise_rules_vendor.cil" >> "$CIL"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"
