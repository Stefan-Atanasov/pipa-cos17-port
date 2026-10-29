#!/bin/sh
# Phase 3b: the panel drops to 60 Hz when idle also after a screen-off (BUGS-TODO B11 follow-up), on top of 3a (system
# + system_ext).
#
# * system_ext/priv-app/SystemUI/SystemUI.apk: SystemUI's SmoothTransitionController paused ColorOS touch idle (OTI)
#   on "power_off" without its 1.5 s auto-resume. Only a later "waking up" resumed it, and SystemUI ignores a wake-up
#   while it still has isScreenON. Then OTI stayed paused (VrrState source 5 = 1, TouchIdleShouldPauseForce) and the
#   panel stayed at 120/144 Hz. module/tools/patch_systemui_oti.py lets "power_off" resume too (goto -> nop nop, dex
#   changed in place, signing block kept). The prebuilt oat/ is deleted (its dex checksum no longer agrees).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3b (early.sh clears the package cache).
#
# Old layer script: build_beta5_3b.sh
#NEEDS: "$TOOLS/patch_systemui_oti.py"
set -eu
. "$PORT/lib.sh"
STEP=3b
SUI_MD5=ed18c6157d5ac4f1e86ce220bc5a0336   # SystemUI.apk of C.06 (unchanged up to 3a)
SUI_NEW=8959d9febe0834ae025d4d2ecf5ca4d4   # after patch_systemui_oti.py

S=$T/system
SE=$T/system_ext

echo "== SystemUI: OTI resumes after power_off"
D=$SE/priv-app/SystemUI
A=$D/SystemUI.apk
# patch_systemui_oti.py finds its site by pattern (exactly once). C.06: the output md5 is a regression check.
sui_in=$(md5sum "$A" | cut -d' ' -f1)
python3 -I "$HERE/../module/tools/patch_systemui_oti.py" "$A" "$R/SystemUI.apk"
SUI_OUT=$(md5sum "$R/SystemUI.apk" | cut -d' ' -f1)
if [ "$sui_in" = "$SUI_MD5" ]; then
    [ "$SUI_OUT" = "$SUI_NEW" ] || { echo "C.06: patched SystemUI.apk md5 differs ($SUI_OUT)"; exit 1; }
else
    echo "NOTE SystemUI.apk $sui_in is not C.06 -> $SUI_OUT (pattern-checked); test OTI after a screen-off"
fi
cat "$R/SystemUI.apk" > "$A"
rm -f "$R/SystemUI.apk"
rm -rf "$D/oat"
echo "SystemUI.apk $SUI_OUT, oat/ removed"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

