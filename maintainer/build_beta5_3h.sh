#!/bin/sh
# Phase 3h: HDR video like on HyperOS (BUGS-TODO 29), on top of 3g (product only). Run as root:
#
#   sudo sh build_beta5_3h.sh
#
# beta4 set ro.surface_flinger.has_HDR_display=false (system and vendor build.prop; HyperOS: true). Codec2InfoBuilder
# (libsfplugin_ccodec) then hides all HDR decoder profiles (HEVC HDR10/HDR10+, VP9 HDR, AV1 HDR10), so apps never pick
# HDR streams. Tested live 2026-10-28 with resetprop: profiles back, HDR10 clip composited by the HWC as BT2020_PQ,
# HDR/SDR boost 2.25 (HyperOS value). has_wide_color_display stays false (the QDCM colour tuning depends on it).
# * product/etc/build.prop: ro.surface_flinger.has_HDR_display=true (product loads after system and vendor).
# * system_ext/etc/build.prop is not changed: ro.pipa.port.layer stays 3g (no system APK changed).
#
# Input: port-work/${TAG}-3g/img. Output: port-work/${TAG}-3h/.
set -eu
TAG=${TAG:-beta5}
STEP=3h
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
PREV=$P/${TAG}-3g
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$PREV/img/product.img" ] && [ -f "$PREV/img/super.img" ] || { echo "3g is missing"; exit 1; }
free=$(df --output=avail -k "$P" | tail -1)
[ "$free" -gt $((20 * 1024 * 1024)) ] || { echo "less than 20 GB free in $P: a full disk truncates super.img"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
echo "== product: extract (3g product.img)"
fsck.erofs --extract="$W/tree/product" --xattrs --preserve "$PREV/img/product.img"
BP=$W/tree/product/etc/build.prop

echo "== 29: has_HDR_display=true"
if grep -q "^ro.surface_flinger.has_HDR_display=" "$BP"; then echo "product build.prop already sets has_HDR_display"; exit 1; fi
{ cat "$BP"; printf '%s\n' "# pipa port 3h (BUGS-TODO 29): HDR decoder profiles and HDR output as on HyperOS" "ro.surface_flinger.has_HDR_display=true"; } > "$W/report/build.prop.new"
cat "$W/report/build.prop.new" > "$BP"   # same inode: label kept
tail -2 "$BP"

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$W/tree/product" > "$W/report/product.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/product.tsv" | wc -l)
echo "product: $(wc -l < "$W/report/product.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (product); system, system_ext, vendor, odm from 3g"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/product.img" "$W/tree/product" > "$W/report/mkfs_product.log" 2>&1
for p in system system_ext vendor odm; do cp --reflink=auto "$PREV/img/$p.img" "$W/img/$p.img"; done
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
