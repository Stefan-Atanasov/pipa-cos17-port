#!/bin/sh
# Phase 2p: Xiaomi pen battery in the ColorOS live alert (fluid cloud), on top of 2o. Run as root:
#
#   sudo sh build_beta5_2p.sh
#
# * my_product/priv-app/IPeManager: OPPO's pen app shows its own fluid-cloud battery capsule only after its OPPO BLE
#   link to the pen works (the Xiaomi pen does not have it). ipe-fluid/patch_ipemanager.py changes k0.h0 so that a
#   present event shows the capsule with the level from global ipe_pencil_battery_level (in-place dex patch, same
#   size; OPPO's platform signature block is kept, Android does not verify system-partition APKs at boot). The
#   prebuilt oat/ (vdex of the old dex) is removed; ART compiles the app on the device.
# * pipa_port PEN_FLUID: on each dock and undock, write ipe_pencil_battery_level and send the present event; sets
#   global pipa_pen_fluid=1.
# * pipa helper 0.5: no own pen pill while pipa_pen_fluid=1 (the low-battery notification stays).
# 2026-10-24 live test (bind mounts): capsule with pen icon and battery % on each dock/undock; hides by itself.
#
# Input: port-work/${TAG}-2o/tree/{system,system_ext,product}, port-work/${TAG}-2o/img, helper/out/PipaHelper.apk.
# Output: port-work/${TAG}-2p/.
set -eu
TAG=${TAG:-beta5}
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2o/img
W=$P/${TAG}-2p
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
APK=$HERE/../helper/out/PipaHelper.apk
OWNER=${PIPA_OWNER:-stefan:stefan}
IPE_STOCK_MD5=4bb067823603d6cb992e16c273229114   # C.06 (17.0.0.103) IPeManager 17.4.0
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2o.sh first"; exit 1; }
[ -f "$APK" ] || { echo "build the helper first: sh helper/build.sh"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2o/tree/system" "$P/${TAG}-2o/tree/system_ext" "$P/${TAG}-2o/tree/product" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== IPeManager: fluid-cloud pen capsule"
IPE=$S/my_product/priv-app/IPeManager
md5=$(md5sum "$IPE/IPeManager.apk" | cut -d' ' -f1)
[ "$md5" = "$IPE_STOCK_MD5" ] || { echo "IPeManager.apk md5 $md5 is not the stock one: check the patch on this donor"; exit 1; }
python3 -I "$HERE/ipe-fluid/patch_ipemanager.py" "$IPE/IPeManager.apk" "$W/report/IPeManager.patched.apk"
cat "$W/report/IPeManager.patched.apk" > "$IPE/IPeManager.apk"   # in place (cat >): owner, mode and SELinux label stay
rm -rf "$IPE/oat"
md5sum "$IPE/IPeManager.apk"

echo "== pipa helper 0.5"
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"
md5sum "$S/system/priv-app/PipaHelper/PipaHelper.apk"

echo "== pipa_port: PEN_FLUID"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
grep -q pen_fluid "$SE/pipa_port/service.sh"
grep -q '^PEN_FLUID=1' "$SE/pipa_port/config.prop"

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
