#!/bin/sh
# Phase 2z: the panel drops to 60 Hz when the screen is idle (BUGS-TODO B11), on top of 2x (system + system_ext).
# Run as root:
#
#   sudo sh build_beta5_2z.sh
#
# * system/my_product/etc/oplus_vrr_config.json: ColorOS touch idle (OTI) switched only the render rate to 60 (the
#   panel stayed at 120 Hz), because its HW strategy needs 110+ nits (an OLED flicker guard; the ColorOS nit estimate
#   on pipa is low). module/tools/patch_vrr_config.py sets hw_nit_limit/hw_nit_limit_pwm to -1 and removes
#   histogram_enable (the nit tables). Then the panel goes to the 60 Hz mode 2.5 s after the last touch.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2z (early.sh clears the package cache).
#
# Input: port-work/${TAG}-2x/tree/system + system_ext, port-work/${TAG}-2t/img (product, vendor, odm).
# Output: port-work/${TAG}-2z/.
set -eu
TAG=${TAG:-beta5}
STEP=2z
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLS=$HERE/../module/tools
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-2x/tree/system" ] && [ -d "$P/${TAG}-2x/tree/system_ext" ] || { echo "the 2x tree is missing: rebuild 2x"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2x/tree/system" "$P/${TAG}-2x/tree/system_ext" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== oplus_vrr_config.json: touch idle may switch the panel mode at any brightness"
F=$S/my_product/etc/oplus_vrr_config.json
python3 -I "$TOOLS/patch_vrr_config.py" "$F" "$W/report/oplus_vrr_config.json.new"
cat "$W/report/oplus_vrr_config.json.new" > "$F"   # in place (cat >): owner, mode and SELinux label stay
md5sum "$F"
getfattr -n security.selinux --only-values "$F"; echo

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
BP=$SE/etc/build.prop
sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$STEP/" "$BP" > "$W/report/build.prop.new"
cat "$W/report/build.prop.new" > "$BP"
grep "^ro.pipa.port.layer=$STEP\$" "$BP"

echo "== label check"
for t in system system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system, system_ext)"
for t in system system_ext; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
