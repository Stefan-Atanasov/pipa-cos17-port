#!/bin/sh
# Phase 2w: idle-drain fix (no knuckle sensor) and the SukiSU manager on the first boot, on top of 2v (system +
# system_ext).
#
# * system/framework/oplus-services.jar: OplusIgnoreFoldTouch asks OPPO's fold-angle sensor type 33171038, which is
#   Xiaomi's always-on "knuckle" sensor on pipa; the sensor hub (SLPI) then sleeps only 1-40 % with the screen off.
#   module/tools/patch_foldtouch.py changes the type to an unused one (live test 2026-10-28: SLPI asleep ~100 %).
# * system_ext/pipa_port/SukiSU.apk + service.sh (KSU_MANAGER): pipa_port installs the SukiSU-Ultra manager (v4.3.0 / 41100 since 2026-10-29; was 4.2.1-r1)
#   once as a normal app (/data/app), where KernelSU finds it. 2v had no manager (2u's system preload gave no root).
# * system_ext/etc/build.prop: ro.pipa.port.layer=2w (early.sh clears the package cache).
#
# Old chain lineage: 2w took its system from 2s (so without the 2u preload) and its system_ext from 2v. In one
# tree this is the same, because step 2u is skipped by default.
#
# Old layer script: build_beta5_2w.sh
#NEEDS: "$TOOLS/patch_foldtouch.py" "$HERE/../kernel/sukisu-v4.3.0/SukiSU_v4.3.0_41100-release.apk" "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=2w
KSU_APK=$HERE/../kernel/sukisu-v4.3.0/SukiSU_v4.3.0_41100-release.apk
KSU_VER=41100   # versionCode of KSU_APK; pipa_port installs it over an older manager
[ -f "$KSU_APK" ] || die "SukiSU manager APK missing: $KSU_APK"
KSU_MD5=$(md5sum "$KSU_APK" | cut -d' ' -f1)

S=$T/system
SE=$T/system_ext

echo "== oplus-services.jar: no knuckle sensor (OplusIgnoreFoldTouch)"
J=$S/system/framework/oplus-services.jar
python3 -I "$TOOLS/patch_foldtouch.py" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
md5sum "$J"
if ls "$S/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then echo "prebuilt oat for oplus-services exists"; exit 1; fi

echo "== pipa_port: SukiSU manager on the first boot"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
need_grep 'pm install -r "$MODDIR/SukiSU.apk"' "$SE/pipa_port/service.sh"
need_grep '^KSU_MANAGER=1$' "$SE/pipa_port/config.prop"
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
A=$SE/pipa_port/SukiSU.apk
cp "$KSU_APK" "$A"
chown 0:0 "$A"; chmod 644 "$A"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$A"
V=$SE/pipa_port/SukiSU.version
echo "$KSU_VER" > "$V"
chown 0:0 "$V"; chmod 644 "$V"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$V"
[ "$(md5sum "$A" | cut -d' ' -f1)" = "$KSU_MD5" ] || die "SukiSU.apk copy has a wrong md5"
echo "SukiSU.apk $KSU_MD5"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

