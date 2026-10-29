#!/bin/sh
# Phase 2c: two small ROM fixes on top of beta5-2b (BUGS-TODO.md B9, B6).
#
# B9 interconnect (call/SMS sharing): bluetooth is denied `find` on ISubsysRadio
#    (tcontext ISubsysService, enforcing). The type is declared in system_ext policy, which already
#    lets nfc, platform_app and others find it; bluetooth is added in the pipa port block.
# B6 native pen lock: ColorOS locks the refresh rate for a stylus when refresh_rate_config.xml's
#    <config> has ipePencilRateId (its own comment: 平板手写笔锁帧120hz, 默认无配置).
#    OplusRefreshRatePolicyImpl.iPEPencilConnectOrPWMMode applies that rate id (3 = 120 Hz) while
#    the pencil counts as connected (global settings_enable_oppo_pencil) and the current rate is
#    90/144/165/185. The Xiaomi pen senses only at 60/120 Hz. power-tune sets the setting while the
#    pen is out of the dock; this build adds the rate id.
#
# Old layer script: build_beta5_2c.sh
set -eu
. "$PORT/lib.sh"



echo "== B9 bluetooth -> ISubsysService"
for f in system_ext/etc/selinux/system_ext_sepolicy.cil system_ext/etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$T/$f" ] || { echo "skip    $f (absent)"; continue; }
    grep -q '^(type ISubsysService)' "$T/$f" || { echo "$f: ISubsysService not declared"; exit 1; }
    replace_once $f '(allow domain oplus_vrr_service (service_manager (find)))\n' \
        '(allow domain oplus_vrr_service (service_manager (find)))\n;; B9: call/SMS sharing over Bluetooth needs the virtual modem service\n(allow bluetooth ISubsysService (service_manager (find)))\n'
done

echo "== B6 native stylus refresh lock"
replace_once system/my_product/etc/refresh_rate_config.xml \
    '<config extremeHighEnable="true" maxrefreshsettings="4"' \
    '<config ipePencilRateId="3" extremeHighEnable="true" maxrefreshsettings="4"'

