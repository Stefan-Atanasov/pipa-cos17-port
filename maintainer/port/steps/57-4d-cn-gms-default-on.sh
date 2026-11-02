#!/bin/sh
# Phase 4d: Google services (CN GMS) are on after a clean flash (BUGS-TODO 49, public bug doc 2026-11-02; system only).
#
# ColorOS CN reads my_product/etc/config/sys_gms_download_app_whitelist.xml; <switch value="disable"/> makes
# OplusDisablePackageManager.fixDisableStateWhenBoot() disable GMS on the first boot. "enable" leaves GMS on; the
# Settings switch (system customize_control_cn_gms) stays, so a user can still turn GMS off. Clean flash only (the
# first boot decides); a dirty flash keeps the user's state.
#NEEDS: "$PORT/lib.sh"
set -eu
. "$PORT/lib.sh"

F=$T/system/my_product/etc/config/sys_gms_download_app_whitelist.xml
replace_once "$F" '<switch value="disable" />' '<switch value="enable" />'
need_grep '<switch value="enable" />' "$F"
