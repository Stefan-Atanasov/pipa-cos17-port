#!/bin/sh
# Phase 2l: smoothness (2026-10-24 stutter root cause, kernel/KERNEL-RESEARCH.md "2026-10-24 morning"), on top of 2k.
# Run as root:
#
#   sudo sh build_beta5_2l.sh
#
# * pipa_port: SF_BIG_CORES sets the UI First kernel scene SA_GPU_COMPOSITION at boot, so SurfaceFlinger and
#   RenderEngine (realtime) stay off the little cores (OPPO's vendor daemon sets it on OPPO phones; pipa's vendor never
#   does). FrameTimeline: SF dropped frames -58 %, GPU-deadline misses -52 %, power +2 % under heavy use.
# * product build.prop (loads after vendor, whose HyperOS values would win otherwise): SF early/earlyGl phase offset
#   -6.5 ms (GPU-composed animation frames missed the vblank with -4 ms), early app offsets -1.5 ms (apps keep their
#   draw time), predict_hwc_composition_strategy=1 (vendor forces 0; 2j's system_ext value never applied).
#
# Input: port-work/${TAG}-2k/tree/{system,system_ext}, port-work/${TAG}-2k/img. Output: port-work/${TAG}-2l/.
set -eu
TAG=${TAG:-beta5}
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2k/img
W=$P/${TAG}-2l
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2k.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2k/tree/system" "$P/${TAG}-2k/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext
echo "== product: extract"
fsck.erofs --extract="$W/tree/product" --xattrs --preserve "$IMGSRC/product.img"
PR=$W/tree/product

# in place (cat >): owner, mode and SELinux label stay
echo "== pipa_port"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
grep -q SF_BIG_CORES "$SE/pipa_port/service.sh"

echo "== product build.prop: SurfaceFlinger timing"
BP=$PR/etc/build.prop
grep -q 'high_fps_early_gl_phase_offset_ns' "$BP" && { echo "already patched"; exit 1; }
printf '%s\n' '' '# pipa port 2l: SF timing for GPU-composed animation frames (vendor sets -4 ms everywhere; 2026-10-24 A/B)' \
    'debug.sf.high_fps_early_phase_offset_ns=-6500000' 'debug.sf.high_fps_early_gl_phase_offset_ns=-6500000' \
    'debug.sf.high_fps_early_app_phase_offset_ns=-1500000' 'debug.sf.high_fps_early_gl_app_phase_offset_ns=-1500000' \
    'debug.sf.predict_hwc_composition_strategy=1' >> "$BP"
tail -6 "$BP"

echo "== label check"
for t in system_ext product; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system_ext, product)"
for t in system_ext product; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in system vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
