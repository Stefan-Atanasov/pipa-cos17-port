#!/bin/sh
# Phase 3f: Game Filter, face crash guard, Bedtime reset, enforcing pipa_port, on top of 3e (system + system_ext).
#
# * 22 Game Filter / colour enhancement did nothing: OPPO applies them in the panel PQ block (SF transaction 22031 ->
#   IDisplayPanelFeature 35); pipa has no such HAL. system/framework/oplus-services.jar: gamefilter/patch_gamefilter.sh
#   adds com.oplus.vrr.PipaGameFilter (a DisplayTransformManager colour-matrix level, 151) and calls it from
#   OPlusSurfaceFlingerController.setGameFilter(int). Tested live 2026-10-28 (set, and reset when the token dies).
# * 8 face enrollment crash (SIGSEGV in crop_eyes): system_ext/pipa_port/facehal/lib64/libpipa_eyeguard.so
#   (port-module/src/eyeguard.c) + service.sh (LD_PRELOAD).
# * 13 Bedtime reset at each Eye Protect start: system_ext/app/OplusEyeProtect: module/tools/patch_eyeprotect.py (f2 and
#   D1 calls in OplusEyeProtectApp.j() -> nop); oat/ removed. Tested live 2026-10-28 (stock 1 -> 0, patched stays 1).
# * 12 pipa_port SELinux domain enforcing: sepolicy/pipa_port_enforce.py (84 rules from a full permissive boot);
#   compiled on the tablet with secilc and tested live with ksud "enforce pipa_port": no denials.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3f.
#
# Old layer script: build_beta5_3f.sh
#NEEDS: "$HERE/gamefilter/patch_gamefilter.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar" "$ROM/pipa_port/facehal/lib64/libpipa_eyeguard.so" "$ROM/pipa_port/service.sh" "$TOOLS/patch_eyeprotect.py" "$HERE/sepolicy/pipa_port_enforce.py" "$HERE/sepolicy/pipa_port_rules.cil"
set -eu
. "$PORT/lib.sh"
STEP=3f

S=$T/system/system
SE=$T/system_ext

# The old 3f took system from the 3c tree and checked `cmp 3c/img/system.img 3e/img/system.img`
# ("3d and 3e did not change system"). File-level version: the system tree must be unchanged since 3c.
[ -f "$ORIG/system.fp-after-3c" ] || die "no $ORIG/system.fp-after-3c: step 3c did not run in this tree"
[ "$(fingerprint "$T/system")" = "$(cat "$ORIG/system.fp-after-3c")" ] || die "system tree changed between 3c and 3f (a step after 3c touched it): the old 3f assumed it did not"

# 3g needs the system_ext CIL as the 3e tree had it (before this step enforces pipa_port). 3d is the last step
# before this one that edits the CIL; 3e does not. Save it here, before the "12:" block below, for step 3g.
mkdir -p "$ORIG"
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    if [ -f "$SE/etc/selinux/$f" ]; then cp -p "$SE/etc/selinux/$f" "$ORIG/$f"; echo "saved   orig/$f (the 3e state, for step 3g)"; fi
done
[ -f "$ORIG/system_ext_sepolicy.cil" ] || die "system_ext_sepolicy.cil missing"

echo "== 22: oplus-services.jar Game Filter bridge"
J=$S/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/gamefilter/patch_gamefilter.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
if ls "$S/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then echo "prebuilt oat for oplus-services exists"; exit 1; fi
md5sum "$J"

echo "== 8: face eye-ROI guard"
L=$SE/pipa_port/facehal/lib64
cp "$ROM/pipa_port/facehal/lib64/libpipa_eyeguard.so" "$L/"
chmod 0644 "$L/libpipa_eyeguard.so"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$L/libpipa_facecrop.so")" "$L/libpipa_eyeguard.so"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'libpipa_eyeguard.so' "$SE/pipa_port/service.sh"
echo "added   system_ext/pipa_port/facehal/lib64/libpipa_eyeguard.so, updated service.sh"

echo "== 13: Eye Protect keeps Bedtime"
E=$SE/app/OplusEyeProtect
python3 -I "$TOOLS/patch_eyeprotect.py" "$E/OplusEyeProtect.apk" "$R/OplusEyeProtect.apk"
cat "$R/OplusEyeProtect.apk" > "$E/OplusEyeProtect.apk"
rm -rf "$E/oat"
md5sum "$E/OplusEyeProtect.apk"

echo "== 12: pipa_port enforcing"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    if grep -q "(type pipa_port)" "$SE/$f"; then
        python3 -I "$HERE/sepolicy/pipa_port_enforce.py" "$SE/$f"
    else
        echo "skip    $f (no pipa_port block)"
    fi
done
if grep -q "(typepermissive pipa_port)" "$SE/etc/selinux/system_ext_sepolicy.cil"; then echo "still permissive"; exit 1; fi

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

