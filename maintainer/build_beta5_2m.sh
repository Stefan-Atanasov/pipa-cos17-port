#!/bin/sh
# Phase 2m: SurfaceFlinger layer caching off again, on top of 2l (system_ext only). Run as root:
#
#   sudo sh build_beta5_2m.sh
#
# 2j put debug.sf.enable_layer_caching=1 into system_ext/etc/build.prop (small gain in the 2026-10-24 night A/B). With
# it on, the user saw the screen glitch in Settings while searching (keyboard + split layout); `service call
# SurfaceFlinger 1040 i32 0` (caching off live, "Planner is disabled") fixed it. Drop the line; AOSP default is off.
#
# Input: port-work/${TAG}-2l/tree/{system,system_ext}, port-work/${TAG}-2l/img. Output: port-work/${TAG}-2m/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2h, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2l/img
W=$P/${TAG}-2m
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2l.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2l/tree/system" "$P/${TAG}-2l/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== system_ext build.prop: layer caching off"
BP=$SE/etc/build.prop
grep -q '^debug.sf.enable_layer_caching=1' "$BP" || { echo "layer caching line not found"; exit 1; }
grep -v '^debug.sf.enable_layer_caching=' "$BP" > "$W/report/system_ext.prop"
cat "$W/report/system_ext.prop" > "$BP"   # in place: owner, mode and SELinux label stay
grep -n 'debug.sf' "$BP"

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$SE" > "$W/report/system_ext.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/system_ext.tsv" | wc -l)
echo "system_ext: $(wc -l < "$W/report/system_ext.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (system_ext)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system_ext.img" "$SE" > "$W/report/mkfs_system_ext.log" 2>&1
for p in system product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
