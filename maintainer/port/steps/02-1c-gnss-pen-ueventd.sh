#!/bin/sh
# Phase 1c: three pipa_core runtime tasks moved into the ROM (notes/PHASE2-ROM-INTEGRATION.md A1, A2, A4).
#
# A1 system_ext loc_sys_service.rc: don't start the GNSS service (pipa has no GNSS hardware; it
#    retries ILocAidlGnss once a second, ~2.4 log lines/s). pipa_core still stops it; harmless.
# A2 vendor ueventd.rc: pen charger sysfs nodes owned by system, 0664, set by ueventd itself instead
#    of pipa_core's post-fs-data chown/chmod. pipa_core's chown then changes nothing.
# A4 system/app/FaceUnlock: the legacy socket face client (com.pipa.faceunlock, R4). The facehal-rs
#    AIDL HAL replaced it; the power-tune module only keeps it disabled.
#    (The old 1c script did A4 only with DROP_FACEUNLOCK=1. The chain never set it, and step 2a does A4.
#    The switch is gone: see NOTES-refactor.md.)
#
# Old layer script: build_beta5_1c.sh
set -eu
. "$PORT/lib.sh"



echo "== A1 GNSS service"
replace_once system_ext/etc/init/loc_sys_service.rc \
    'on early-boot\n    start loc_sys_service\n' \
    '# pipa port: no GNSS hardware; the service retries ILocAidlGnss once a second\non early-boot\n#    start loc_sys_service\n'

echo "== A2 pen sysfs permissions"
grep -q 'fuda' "$T/vendor/etc/ueventd.rc" && { echo "ueventd.rc already mentions fuda"; exit 1; }
python3 -I - "$T/vendor/etc/ueventd.rc" <<'PY'
import sys
p = sys.argv[1]
add = """
# pipa port: pen wireless charger nodes written by system_server (was a chown in pipa_core)
/sys/class/power_supply/fuda      reverse_chg_mode        0664    system    system
/sys/class/power_supply/fuda      reverse_pen_soc         0664    system    system
/sys/class/power_supply/wireless  pen_mac                 0664    system    system
/sys/class/power_supply/wireless  reverse_pen_chg_state   0664    system    system
"""
with open(p, 'a', encoding='utf-8') as f:   # same inode: label kept
    f.write(add)
PY
echo "edited  vendor/etc/ueventd.rc"
