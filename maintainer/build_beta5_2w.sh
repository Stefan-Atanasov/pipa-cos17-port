#!/bin/sh
# Phase 2w: idle-drain fix (no knuckle sensor) and the SukiSU manager on the first boot, on top of 2v (system +
# system_ext). Run as root:
#
#   sudo sh build_beta5_2w.sh
#
# * system/framework/oplus-services.jar: OplusIgnoreFoldTouch asks OPPO's fold-angle sensor type 33171038, which is
#   Xiaomi's always-on "knuckle" sensor on pipa; the sensor hub (SLPI) then sleeps only 1-40 % with the screen off.
#   module/tools/patch_foldtouch.py changes the type to an unused one (live test 2026-10-28: SLPI asleep ~100 %).
# * system_ext/pipa_port/SukiSU.apk + service.sh (KSU_MANAGER): pipa_port installs the SukiSU-Ultra manager 4.2.1-r1
#   once as a normal app (/data/app), where KernelSU finds it. 2v had no manager (2u's system preload gave no root).
# * system_ext/etc/build.prop: ro.pipa.port.layer=2w (early.sh clears the package cache).
#
# Input: port-work/${TAG}-2s/tree/system (= the 2v system image), port-work/${TAG}-2v/tree/system_ext,
# port-work/${TAG}-2t/img (product, vendor, odm), COS17/kernel/sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk.
# Output: port-work/${TAG}-2w/.
set -eu
TAG=${TAG:-beta5}
STEP=2w
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
TOOLS=$HERE/../module/tools
KSU_APK=$HERE/../kernel/sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-2s/tree/system" ] || { echo "the 2s system tree is missing: rebuild 2s"; exit 1; }
[ -d "$P/${TAG}-2v/tree/system_ext" ] || { echo "the 2v tree is missing: rebuild 2v"; exit 1; }
[ -f "$KSU_APK" ] || { echo "SukiSU manager APK missing: $KSU_APK"; exit 1; }
KSU_MD5=$(md5sum "$KSU_APK" | cut -d' ' -f1)

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2s/tree/system" "$P/${TAG}-2v/tree/system_ext" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== oplus-services.jar: no knuckle sensor (OplusIgnoreFoldTouch)"
J=$S/system/framework/oplus-services.jar
python3 -I "$TOOLS/patch_foldtouch.py" "$J" "$W/report/oplus-services.jar.new"
cat "$W/report/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
md5sum "$J"
if ls "$S/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then echo "prebuilt oat for oplus-services exists"; exit 1; fi

echo "== pipa_port: SukiSU manager on the first boot"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
grep -q 'pm install "$MODDIR/SukiSU.apk"' "$SE/pipa_port/service.sh"
grep -q '^KSU_MANAGER=1$' "$SE/pipa_port/config.prop"
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
A=$SE/pipa_port/SukiSU.apk
cp "$KSU_APK" "$A"
chown 0:0 "$A"; chmod 644 "$A"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$A"
[ "$(md5sum "$A" | cut -d' ' -f1)" = "$KSU_MD5" ]
echo "SukiSU.apk $KSU_MD5"

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
