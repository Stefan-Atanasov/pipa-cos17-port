#!/bin/sh
# Phase 1 of "fixes in the ROM": beta5 + the power-tune module's five file fixes baked into the images.
#
# Also bakes ROM-side fixes from the audit (phase 1b): R12 facehal verbose off, U11 6 GB zram size,
# R11 /data/ota_package/OTA created by init. U1 (zz_portdebug.rc) is already absent from beta5.
#
# Each fix overwrites the file's content in place (same inode), so its SELinux label, owner and mode
# stay those of the stock file. Every target must have its known stock md5 first, otherwise the
# step stops: a different base means the fix has to be regenerated with module/tools/.
#
# Baked (module README §6, §7, §12, §13, §14):
#   vendor/etc/qdcm_calib_data_xiaomi_m82_{36_02_0a,42_02_0b}_*.xml   Natural colour = sRGB matrix
#   vendor/etc/audio_policy_volumes.xml                              USB headset / A2DP volume curves
#   vendor/lib/hw/audio.primary.kona.so                              speaker L/R at rotation 270
#   system_ext/etc/display_brightness_config_default.xml             brightness curve, ~1 nit min
#   system/framework/oplus-services.jar                              CCT sensor reroute (C.06 jar; the base step
#                                                                    already put the IEngineer fix in it)
# The module (v0.10) keeps working on this build: its binds become no-ops (cmp equal), and the jar is
# skipped because the ROM jar's md5 is already the patched one. The runtime guards stay in the module.
#
# Input change: the old script extracted vendor_b.img and odm_b.img itself; port.sh does that once for
# all steps. The input trees are the same pinned images.
#
# Old layer script: build_beta5_baked.sh
#NEEDS: "$MOD/system/vendor/etc/qdcm_calib_data_xiaomi_m82_36_02_0a_video_mode_dual_dsi_dphy_panel.xml" "$MOD/system/vendor/etc/qdcm_calib_data_xiaomi_m82_42_02_0b_video_mode_dual_dsi_dphy_panel.xml" "$MOD/system/vendor/etc/audio_policy_volumes.xml" "$MOD/system/vendor/lib/hw/audio.primary.kona.so" "$MOD/system/system_ext/etc/display_brightness_config_default.xml" "$MOD/tools/patch_framework.sh"
set -eu
. "$PORT/lib.sh"
QDCM36=qdcm_calib_data_xiaomi_m82_36_02_0a_video_mode_dual_dsi_dphy_panel.xml
QDCM42=qdcm_calib_data_xiaomi_m82_42_02_0b_video_mode_dual_dsi_dphy_panel.xml

# bake <tree path> <module file> <stock md5> <baked md5>
bake() {
    t="$T/$1"
    [ -f "$t" ] || die "missing $1"
    [ "$(md5sum < "$2" | cut -c1-32)" = "$4" ] || die "module copy of $1 is not $4"
    have=$(md5sum < "$t" | cut -c1-32)
    [ "$have" = "$3" ] || die "$1: md5 $have, expected stock $3; regenerate the fix"
    before=$(stat -c '%a %u:%g' "$t"); lbl=$(getfattr -n security.selinux --only-values "$t")
    cat "$2" > "$t"                                   # same inode: label, owner, mode kept
    [ "$(stat -c '%a %u:%g' "$t")" = "$before" ] && [ "$(getfattr -n security.selinux --only-values "$t")" = "$lbl" ] \
        || die "$1: metadata changed"
    echo "baked   $1  $3 -> $4  ($before $lbl)"
}

echo "== bake"
bake vendor/etc/$QDCM36                 "$MOD/system/vendor/etc/$QDCM36"               c5794bfe43ba58a7a2e45598567a3d81 c102c20fd2fe7cf8ee35c2e5b9e71be5
bake vendor/etc/$QDCM42                 "$MOD/system/vendor/etc/$QDCM42"               151b5080d45b4c61a81492a664dce896 1e2ab685745fa4a6c246c1653be2fc91
bake vendor/etc/audio_policy_volumes.xml "$MOD/system/vendor/etc/audio_policy_volumes.xml" be96e8f857540208cd12faa37b6d3064 6cfda1fd31934b533c7f807d07024516
bake vendor/lib/hw/audio.primary.kona.so "$MOD/system/vendor/lib/hw/audio.primary.kona.so" 8725bcea7b5061fe84cc57b85e2f5266 90c5b882f0d59dbc5088dcb2266305d6
bake system_ext/etc/display_brightness_config_default.xml "$MOD/system/system_ext/etc/display_brightness_config_default.xml" 4714aaaba6efa5793fd3b4dd566f5a0b 4328a940de3b77992dd36c6fdc553c08

# oplus-services.jar: CCT sensor reroute (edits 1-3 of patch_framework.sh; edit 4, IEngineer, is already in from the
# base step). Made from the donor's own jar at build time, so a new donor needs no prebuilt file. On C.06 the
# result must be the old module jar (7afeadb1 -> 8810ad00).
J=$T/system/system/framework/oplus-services.jar
in_md5=$(md5sum < "$J" | cut -c1-32)
before=$(stat -c '%a %u:%g' "$J"); lbl=$(getfattr -n security.selinux --only-values "$J")
PATCH=all sh "$MOD/tools/patch_framework.sh" "$J" "$R/oplus-services.cct.jar"
cat "$R/oplus-services.cct.jar" > "$J"                        # same inode: label, owner, mode kept
[ "$(stat -c '%a %u:%g' "$J")" = "$before" ] && [ "$(getfattr -n security.selinux --only-values "$J")" = "$lbl" ] \
    || die "oplus-services.jar: metadata changed"
out_md5=$(md5sum < "$J" | cut -c1-32)
if [ "$in_md5" = 7afeadb12583df3b1fdd92490e2e76cc ]; then
    [ "$out_md5" = 8810ad003920900595276db5c9d05e5a ] || die "C.06: CCT patch gave an unexpected jar ($out_md5)"
fi
echo "patched oplus-services.jar  $in_md5 -> $out_md5  ($before $lbl)"
[ ! -e "$T/system/system/framework/oat/arm64/oplus-services.odex" ] || die "stale oplus-services.odex present"

echo "== bake ROM fixes (phase 1b)"
# R12: the face HAL's verbose logging was left on in beta4/beta5
replace_once system/system/build.prop 'persist.sys.facehal.verbose=true\n' 'persist.sys.facehal.verbose=false\n'

# U11: the port's mm-sys script gives every unit <= 8 GB RAM an 8 GB zram. 6 GB units get 4 GB,
# which is what HyperOS stock uses (RAM/2, capped at 4 GB). 8 GB units are unchanged.
# (The odm tree is the pinned beta4 odm_b.img, extracted by port.sh.)
[ "$(md5sum < "$T/odm/etc/init.oplus.mm-sys.sh" | cut -c1-32)" = 3ad05955c50d69cca63aaeeefca46605 ] \
    || die "odm init.oplus.mm-sys.sh is not the beta4 one"
replace_once odm/etc/init.oplus.mm-sys.sh \
    '\tif [ "$MEM_TOTAL" -le 8388608 ]; then\n\t\tswap_size_mb=8192\n' \
    '\tif [ "$MEM_TOTAL" -le 6291456 ]; then\n\t\t# pipa maintainer: 6 GB units get 4 GB like HyperOS stock (RAM/2, max 4 GB)\n\t\tswap_size_mb=4096\n\telif [ "$MEM_TOTAL" -le 8388608 ]; then\n\t\tswap_size_mb=8192\n'

# R11: com.oplus.ota reports 0 bytes free when /data/ota_package/OTA is missing (false "storage
# space is less than ..." dialog). init.rc creates /data/ota_package but not OTA/. New rc file,
# labelled, owned and moded like its neighbour.
RC=system_ext/etc/init/pipa_port_ota_dir.rc
REF="$T/system_ext/etc/init/init.oplus.rootdir.rc"
[ ! -e "$T/$RC" ] || die "$RC exists already"
cat > "$T/$RC" <<'EOF'
# pipa port (maintainer): com.oplus.ota checks free space on /data/ota_package/OTA and treats a
# missing directory as 0 bytes free. init.rc only creates /data/ota_package.
on post-fs-data
    mkdir /data/ota_package/OTA 0770 system cache
EOF
chown --reference="$REF" "$T/$RC"; chmod --reference="$REF" "$T/$RC"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$REF")" "$T/$RC"
echo "added   $RC ($(stat -c '%a %u:%g' "$T/$RC") $(getfattr -n security.selinux --only-values "$T/$RC"))"
