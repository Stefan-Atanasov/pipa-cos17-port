#!/bin/sh
# Phase 3z: "Custom charging limit" and "Smart charging" hold the battery level (BUGS-TODO 50, public bug doc
# 2026-11-02; system_ext only).
#
# ColorOS sends the limits to the OPPO charger HAL (setChgConfig 14 "2++<on>+<level>", setChgConfig 5
# "4++<a>+<level>+<b>+<level>"); the OPPO kernel holds the level. The pipa charger shim answered every setter with 0.
# * port-rom chargershim.jar: the setters record their arguments in /data/misc/pipa_port/chg_*
#   (maintainer/chargershim/patch_record.py on the 2k jar). UI test 2026-11-02: limit on = "2++1+90", off = "2++0+90".
# * service.sh chg_hold (every 30 s, also with the screen off): battery_charging_enabled=0 at the lowest active level,
#   1 again at level-3. The tablet runs from the charger while the hold is on. Config: CHARGE_HOLD=0 turns it off.
# * sepolicy/pipa_port_rules.cil ";; 3z": pipa_port writes battery_charging_enabled (step 3g puts the file into the CIL).
#NEEDS: "$ROM/pipa_port/chargershim.jar" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
cat "$ROM/pipa_port/chargershim.jar" > "$SE/pipa_port/chargershim.jar"
python3 -I - "$SE/pipa_port/chargershim.jar" <<'PY'
import sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read("classes.dex")
assert b"/data/misc/pipa_port/chg_" in d, "chargershim.jar: no 3z record patch"
PY
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep '^chg_hold() {' "$SE/pipa_port/service.sh"
need_grep "(allow pipa_port vendor_sysfs_battery_supply (file (write getattr)))" "$SE/etc/selinux/system_ext_sepolicy.cil"
echo "charger shim records the charge limits; pipa_port holds the level"
