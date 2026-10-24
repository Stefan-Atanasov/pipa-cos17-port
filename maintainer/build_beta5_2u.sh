#!/bin/sh
# Phase 2u: SukiSU-Ultra manager 4.2.1-r1 preinstalled as a removable app, on top of 2t (system + system_ext). Run as root:
#
#   sudo sh build_beta5_2u.sh
#
# * system/my_stock/del-app/SukiSU/SukiSU.apk: ColorOS installs the del-app APKs as normal, removable apps (like
#   Calculator and Clock). After a clean flash the manager that matches the kernel's SukiSU (4.2.1-r1) is there; the
#   user opens it once to install ksud. The user can update or uninstall it.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2u (early.sh clears the package cache).
#
# Input: port-work/${TAG}-2s/tree/system (2s = helper 0.6), port-work/${TAG}-2t/tree/system_ext, port-work/${TAG}-2t/img,
# COS17/kernel/sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk. Output: port-work/${TAG}-2u/.
set -eu
TAG=${TAG:-beta5}
STEP=2u
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
KSU_APK=$HERE/../kernel/sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk
KSU_MD5=$(md5sum "$KSU_APK" | cut -d' ' -f1)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-2s/tree/system" ] || { echo "the 2s system tree is missing: rebuild 2s"; exit 1; }
[ -d "$P/${TAG}-2t/tree/system_ext" ] || { echo "the 2t tree is missing: rebuild 2t"; exit 1; }
[ -f "$KSU_APK" ] || { echo "SukiSU manager APK missing: $KSU_APK"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2s/tree/system" "$P/${TAG}-2t/tree/system_ext" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== SukiSU manager 4.2.1-r1 as a removable preload (my_stock/del-app)"
D=$S/my_stock/del-app/SukiSU
mkdir -p "$D"
cp "$KSU_APK" "$D/SukiSU.apk"
chown 0:0 "$D" "$D/SukiSU.apk"
chmod 755 "$D"; chmod 644 "$D/SukiSU.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$D"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$D/SukiSU.apk"
md5sum "$D/SukiSU.apk"
[ "$(md5sum "$D/SukiSU.apk" | cut -d' ' -f1)" = "$KSU_MD5" ]

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
