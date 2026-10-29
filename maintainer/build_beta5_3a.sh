#!/bin/sh
# Phase 3a: privacy password, app lock and hidden apps work (BUGS-TODO B8), on top of 2z (system + system_ext). Run as
# root:
#
#   sudo sh build_beta5_3a.sh
#
# * system_ext/pipa_port/cryptoeng.jar + service.sh/config.prop (CRYPTOENG): ColorOS keeps the privacy password in
#   OPPO's TEE app behind vendor.oplus.hardware.cryptoeng.ICryptoeng/default, which pipa does not have. pipa_port
#   starts CryptoEngShim (maintainer/cryptoeng, built by its build.sh), which answers the same commands (enroll,
#   verify, modify, delete, get info) and keeps the records in /data/misc/pipa_port/cryptoeng. Online recovery
#   (OPPO account, e-mail) stays unsupported.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3a (early.sh clears the package cache).
#
# Input: port-work/${TAG}-2z/tree/system + system_ext, port-work/${TAG}-2t/img (product, vendor, odm).
# Output: port-work/${TAG}-3a/.
set -eu
TAG=${TAG:-beta5}
STEP=3a
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
CE_JAR=$HERE/cryptoeng/cryptoeng.jar
CE_MD5=2eb17a271c5864589c59ef287ea466c3   # maintainer/cryptoeng/build.sh (JDK 21, build-tools 37.0.0)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-2z/tree/system" ] && [ -d "$P/${TAG}-2z/tree/system_ext" ] || { echo "the 2z tree is missing: rebuild 2z"; exit 1; }
[ "$(md5sum "$CE_JAR" | cut -d' ' -f1)" = "$CE_MD5" ] || { echo "cryptoeng.jar md5 differs: run maintainer/cryptoeng/build.sh, update CE_MD5"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2z/tree/system" "$P/${TAG}-2z/tree/system_ext" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== pipa_port: cryptoeng shim"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
grep -q 'app_process /system/bin CryptoEngShim' "$SE/pipa_port/service.sh"
grep -q '^CRYPTOENG=1$' "$SE/pipa_port/config.prop"
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
A=$SE/pipa_port/cryptoeng.jar
cp "$CE_JAR" "$A"
chown 0:0 "$A"; chmod 644 "$A"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$A"
echo "cryptoeng.jar $CE_MD5"

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
