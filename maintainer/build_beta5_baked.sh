#!/bin/sh
# Phase 1 of "fixes in the ROM": beta5 + the power-tune module's five file fixes baked into the images.
# Run as root after build_beta5.sh:   sudo sh build_beta5_baked.sh
#
# Input:  port-work/${TAG}/tree/{system,system_ext} (root-extracted, labelled; from build_beta5.sh)
#         work/parts/vendor_b.img (beta4 vendor), port-work/${TAG}/img/{product,odm}.img
# Also bakes ROM-side fixes from the audit (phase 1b): R12 facehal verbose off, U11 6 GB zram size,
# R11 /data/ota_package/OTA created by init. U1 (zz_portdebug.rc) is already absent from beta5.
# Output: port-work/${TAG}-baked/{tree,img,report}. Inputs are not modified: the trees are reflink
#         copies (btrfs), so they cost almost no space until written.
#
# Each fix overwrites the file's content in place (same inode), so its SELinux label, owner and mode
# stay those of the stock file. Every target must have its known stock md5 first, otherwise the
# script stops: a different base means the fix has to be regenerated with module/tools/.
#
# Baked (module README §6, §7, §12, §13, §14):
#   vendor/etc/qdcm_calib_data_xiaomi_m82_{36_02_0a,42_02_0b}_*.xml   Natural colour = sRGB matrix
#   vendor/etc/audio_policy_volumes.xml                              USB headset / A2DP volume curves
#   vendor/lib/hw/audio.primary.kona.so                              speaker L/R at rotation 270
#   system_ext/etc/display_brightness_config_default.xml             brightness curve, ~1 nit min
#   system/framework/oplus-services.jar                              CCT sensor reroute (C.06 jar; the plain
#                                                                    beta5 tree already has the IEngineer fix)
# The module (v0.10) keeps working on this build: its binds become no-ops (cmp equal), and the jar is
# skipped because the ROM jar's md5 is already the patched one. The runtime guards stay in the module.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
MOD="$HERE/../module"
SRC=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}
W=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-baked
PARTS="$HERE/../work/parts"
OWNER=${PIPA_OWNER:-stefan:stefan}
QDCM36=qdcm_calib_data_xiaomi_m82_36_02_0a_video_mode_dual_dsi_dphy_panel.xml
QDCM42=qdcm_calib_data_xiaomi_m82_42_02_0b_video_mode_dual_dsi_dphy_panel.xml

[ -d "$SRC/tree/system" ] && [ -d "$SRC/tree/system_ext" ] || { echo "run build_beta5.sh first"; exit 1; }
rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1

echo "== copy trees"
cp -a --reflink=auto "$SRC/tree/system" "$SRC/tree/system_ext" "$W/tree/"
fsck.erofs --extract="$W/tree/vendor" --xattrs --preserve "$PARTS/vendor_b.img"

# bake <tree path> <module file> <stock md5> <baked md5>
bake() {
    t="$W/tree/$1"
    [ -f "$t" ] || { echo "missing $1"; exit 1; }
    [ "$(md5sum < "$2" | cut -c1-32)" = "$4" ] || { echo "module copy of $1 is not $4"; exit 1; }
    have=$(md5sum < "$t" | cut -c1-32)
    [ "$have" = "$3" ] || { echo "$1: md5 $have, expected stock $3; regenerate the fix"; exit 1; }
    before=$(stat -c '%a %u:%g' "$t"); lbl=$(getfattr -n security.selinux --only-values "$t")
    cat "$2" > "$t"                                   # same inode: label, owner, mode kept
    [ "$(stat -c '%a %u:%g' "$t")" = "$before" ] && [ "$(getfattr -n security.selinux --only-values "$t")" = "$lbl" ] \
        || { echo "$1: metadata changed"; exit 1; }
    echo "baked   $1  $3 -> $4  ($before $lbl)"
}

echo "== bake"
bake vendor/etc/$QDCM36                 "$MOD/system/vendor/etc/$QDCM36"               c5794bfe43ba58a7a2e45598567a3d81 c102c20fd2fe7cf8ee35c2e5b9e71be5
bake vendor/etc/$QDCM42                 "$MOD/system/vendor/etc/$QDCM42"               151b5080d45b4c61a81492a664dce896 1e2ab685745fa4a6c246c1653be2fc91
bake vendor/etc/audio_policy_volumes.xml "$MOD/system/vendor/etc/audio_policy_volumes.xml" be96e8f857540208cd12faa37b6d3064 6cfda1fd31934b533c7f807d07024516
bake vendor/lib/hw/audio.primary.kona.so "$MOD/system/vendor/lib/hw/audio.primary.kona.so" 8725bcea7b5061fe84cc57b85e2f5266 90c5b882f0d59dbc5088dcb2266305d6
bake system_ext/etc/display_brightness_config_default.xml "$MOD/system/system_ext/etc/display_brightness_config_default.xml" 4714aaaba6efa5793fd3b4dd566f5a0b 4328a940de3b77992dd36c6fdc553c08
bake system/system/framework/oplus-services.jar "$MOD/framework/2175feb9d4b03eb2859e73e71cfb854d.jar" 7afeadb12583df3b1fdd92490e2e76cc 8810ad003920900595276db5c9d05e5a
[ ! -e "$W/tree/system/system/framework/oat/arm64/oplus-services.odex" ] || { echo "stale oplus-services.odex present"; exit 1; }

# replace_once <tree path> <old> <new>: exact text edit, old must occur exactly once; same inode
replace_once() {
    python3 -I - "$W/tree/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]
old, new = old.encode().decode('unicode_escape'), new.encode().decode('unicode_escape')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != 1:
    sys.exit(f"{p}: anchor found {n} times, expected 1")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s.replace(old, new)); f.truncate()
PY
    [ $? = 0 ] || exit 1
    echo "edited  $1"
}

echo "== bake ROM fixes (phase 1b)"
# R12: the face HAL's verbose logging was left on in beta4/beta5
replace_once system/system/build.prop 'persist.sys.facehal.verbose=true\n' 'persist.sys.facehal.verbose=false\n'

# U11: the port's mm-sys script gives every unit <= 8 GB RAM an 8 GB zram. 6 GB units get 4 GB,
# which is what HyperOS stock uses (RAM/2, capped at 4 GB). 8 GB units are unchanged.
fsck.erofs --extract="$W/tree/odm" --xattrs --preserve "$PARTS/odm_b.img"
[ "$(md5sum < "$W/tree/odm/etc/init.oplus.mm-sys.sh" | cut -c1-32)" = 3ad05955c50d69cca63aaeeefca46605 ] \
    || { echo "odm init.oplus.mm-sys.sh is not the beta4 one"; exit 1; }
replace_once odm/etc/init.oplus.mm-sys.sh \
    '\tif [ "$MEM_TOTAL" -le 8388608 ]; then\n\t\tswap_size_mb=8192\n' \
    '\tif [ "$MEM_TOTAL" -le 6291456 ]; then\n\t\t# pipa maintainer: 6 GB units get 4 GB like HyperOS stock (RAM/2, max 4 GB)\n\t\tswap_size_mb=4096\n\telif [ "$MEM_TOTAL" -le 8388608 ]; then\n\t\tswap_size_mb=8192\n'

# R11: com.oplus.ota reports 0 bytes free when /data/ota_package/OTA is missing (false "storage
# space is less than ..." dialog). init.rc creates /data/ota_package but not OTA/. New rc file,
# labelled, owned and moded like its neighbour.
RC=system_ext/etc/init/pipa_port_ota_dir.rc
REF="$W/tree/system_ext/etc/init/init.oplus.rootdir.rc"
cat > "$W/tree/$RC" <<'EOF'
# pipa port (maintainer): com.oplus.ota checks free space on /data/ota_package/OTA and treats a
# missing directory as 0 bytes free. init.rc only creates /data/ota_package.
on post-fs-data
    mkdir /data/ota_package/OTA 0770 system cache
EOF
chown --reference="$REF" "$W/tree/$RC"; chmod --reference="$REF" "$W/tree/$RC"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$REF")" "$W/tree/$RC"
echo "added   $RC ($(stat -c '%a %u:%g' "$W/tree/$RC") $(getfattr -n security.selinux --only-values "$W/tree/$RC"))"

echo "== label check"
for p in system system_ext vendor odm; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$p" > "$W/report/$p.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | wc -l)
    echo "$p: $(wc -l < "$W/report/$p.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || { awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | head; exit 1; }
done

echo "== mkfs"
for p in system system_ext vendor odm; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$p.img" "$W/tree/$p" > "$W/report/mkfs_$p.log" 2>&1
done
cp "$SRC/img/product.img" "$W/img/"
ls -l "$W/img"

echo "== super"
cd "$W/img"
set --
for p in system system_ext product vendor odm; do set -- "$@" --partition "${p}_a:readonly:0:qti_dynamic_partitions_a"; done
for p in system system_ext product vendor odm; do
    set -- "$@" --partition "${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b" --image "${p}_b=$p.img"
done
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab \
    --device super:9126805504 \
    --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
    "$@" --sparse --output super.img 2>&1 | grep -v -e 'will resize' -e 'Invalid sparse' || true
ls -l super.img
md5sum super.img

chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
