#!/bin/sh
# Phase 3j (TEST): YouTube HDR without glitches (BUGS-TODO 29), on top of 3i (wide colour), vendor only. Run as root:
#
#   sudo sh build_beta5_3j.sh
#
# 3i: YouTube plays HDR, but the PixelOS composer cannot parse SET_LAYER_GENERIC_METADATA (0x040e0000), which the
# ColorOS SurfaceFlinger sends every frame during HDR; parse() then drops the rest of the frame (glitches, no response).
# * vendor/bin/hw/vendor.qti.hardware.display.composer-service: module/tools/patch_composer_genmeta.py (unknown
#   commands are skipped, parsed=true). A changed vendor service cannot be tested from /data (nosuid): layer only.
#
# Input: port-work/${TAG}-3i/img. Output: port-work/${TAG}-3j/.
set -eu
TAG=${TAG:-beta5}
STEP=3j
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
PREV=$P/${TAG}-3i
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$PREV/img/vendor.img" ] && [ -f "$PREV/img/super.img" ] || { echo "3i is missing"; exit 1; }
free=$(df --output=avail -k "$P" | tail -1)
[ "$free" -gt $((20 * 1024 * 1024)) ] || { echo "less than 20 GB free in $P: a full disk truncates super.img"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
echo "== vendor: extract (3i vendor.img)"
fsck.erofs --extract="$W/tree/vendor" --xattrs --preserve "$PREV/img/vendor.img"
C=$W/tree/vendor/bin/hw/vendor.qti.hardware.display.composer-service

echo "== 29: composer skips SET_LAYER_GENERIC_METADATA"
python3 -I "$HERE/../module/tools/patch_composer_genmeta.py" "$C" "$W/report/composer-service.new"
cat "$W/report/composer-service.new" > "$C"   # same inode: owner, mode, label stay
md5sum "$C"

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$W/tree/vendor" > "$W/report/vendor.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/vendor.tsv" | wc -l)
echo "vendor: $(wc -l < "$W/report/vendor.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (vendor); system, system_ext, product, odm from 3i"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/vendor.img" "$W/tree/vendor" > "$W/report/mkfs_vendor.log" 2>&1
for p in system system_ext product odm; do cp --reflink=auto "$PREV/img/$p.img" "$W/img/$p.img"; done
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
    "$@" --sparse --output super.img > "$W/report/lpmake.log" 2>&1 || { cat "$W/report/lpmake.log"; echo "lpmake failed"; rm -f super.img; exit 1; }
grep -v -e 'will resize' -e 'Invalid sparse' "$W/report/lpmake.log" || true
ls -l super.img
md5sum super.img
chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
