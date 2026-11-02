#!/bin/sh
# Phase 4m: charge hold reads the stop field of setChgConfig type 5; charger shim with real battery values, atomic
# records and no stale hold after a reboot (BUGS-TODO 50; system_ext).
#
# * pipa_port service.sh chg_hold: type 5 is "4++<stop>+<level>+<mode>+<level>" (Battery app
#   SmartChargeProtectionController; mode 0 = smart charging, 1 = charging limit). 3z read <mode> as a second on
#   flag, so the release "4++0+L+1+L" kept the charge stopped. Now only <stop> starts a hold. Smart charging itself runs
#   in the Battery app (OplusDeepThinker prediction, alarm release before the usual unplug time).
#   Live test 2026-11-02 (bind + pipa_port restart, battery 37 %): release mode 1 -> charges (3z: stopped);
#   hold mode 1 at 37 -> stops; smart hold 80 -> charges.
# * chargershim.jar (maintainer/chargershim/patch_record.py): getters for level, temperature, Rm, Fcc, current,
#   voltage and getUIsohValue (health % = charge_full / charge_full_design) read sysfs (before: 0); each record is
#   written to chg_<name>.tmp and renamed (the 30 s poll never reads a half file); setters return -1 on a failed write
#   (setChgConfig 12: 1 = ok, EngineerMode tests == 1); at shim start a chg_cfg5 older than this boot is deleted.
#   Live test 2026-11-02 (bind + shim restart): stale hold deleted, shim registered, no error.
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/chargershim.jar"
set -eu
. "$PORT/lib.sh"
STEP=4m

SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'Only <stop> starts a hold' "$SE/pipa_port/service.sh"
cat "$ROM/pipa_port/chargershim.jar" > "$SE/pipa_port/chargershim.jar"
need_grep 'bootCheck' "$SE/pipa_port/chargershim.jar"
set_layer "$STEP"
