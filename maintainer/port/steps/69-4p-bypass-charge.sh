#!/bin/sh
# Phase 4p: bypass charging (BUGS-TODO 50 "not done: bypass"; system_ext).
#
# ColorOS bypass charging (Games app switch, Settings > Battery): the Battery app BypassChargeController sends
# setChgConfig(25, "1+switch=<0|1>") to the OPPO charger HAL; the OPPO kernel plc driver then powers the system from
# the charger and stops the battery charge. Static analysis: notes/cloud/CHARGER-HAL.md (sections C.3 and E).
# * chargershim.jar (maintainer/chargershim/patch_record.py): type 25 returns 1 (the app arms its 180 s re-send
#   watchdog only for a non-zero return), getChgConfig(24) = "1"/"0" from chg_cfg25, getChgConfig(31, "24"|"25") = "1",
#   other getChgConfig calls go to the original method; a chg_cfg25 older than the boot is deleted at shim start.
# * pipa_port service.sh chg_hold: a fresh "1+switch=1" (5-10 min) stops the charge with battery_charging_enabled=0
#   (the input stays on, so the charger powers the tablet); below 15 % it charges; unplugged it enables charging again.
#   Poll every 5 s (was 30 s).
# Gate: app feature com.oplus.fullscene_plc_charge.support in my_product (the donor sets it true; checked here).
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/chargershim.jar"
set -eu
. "$PORT/lib.sh"
STEP=4p

F=$T/system/my_product/etc/extension/com.oplus.app-features.xml
need_grep 'com.oplus.fullscene_plc_charge.support" args="boolean:true"' "$F"
SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'chg_cfg25' "$SE/pipa_port/service.sh"
cat "$ROM/pipa_port/chargershim.jar" > "$SE/pipa_port/chargershim.jar"
need_grep 'bypassStatus' "$SE/pipa_port/chargershim.jar"
set_layer "$STEP"
