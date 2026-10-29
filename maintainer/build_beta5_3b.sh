#!/bin/sh
# Phase 3b: the panel drops to 60 Hz when idle also after a screen-off (BUGS-TODO B11 follow-up), on top of 3a (system
# + system_ext). Run as root:
#
#   sudo sh build_beta5_3b.sh
#
# * system_ext/priv-app/SystemUI/SystemUI.apk: SystemUI's SmoothTransitionController paused ColorOS touch idle (OTI)
#   on "power_off" without its 1.5 s auto-resume. Only a later "waking up" resumed it, and SystemUI ignores a wake-up
#   while it still has isScreenON. Then OTI stayed paused (VrrState source 5 = 1, TouchIdleShouldPauseForce) and the
#   panel stayed at 120/144 Hz. module/tools/patch_systemui_oti.py lets "power_off" resume too (goto -> nop nop, dex
#   changed in place, signing block kept). The prebuilt oat/ is deleted (its dex checksum no longer agrees).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3b (early.sh clears the package cache).
#
# Input: port-work/${TAG}-3a/tree/system + system_ext, port-work/${TAG}-2t/img (product, vendor, odm).
# Output: port-work/${TAG}-3b/.
set -eu
TAG=${TAG:-beta5}
STEP=3b
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
SUI_MD5=ed18c6157d5ac4f1e86ce220bc5a0336   # SystemUI.apk of C.06 (unchanged up to 3a)
SUI_NEW=8959d9febe0834ae025d4d2ecf5ca4d4   # after patch_systemui_oti.py
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-3a/tree/system" ] && [ -d "$P/${TAG}-3a/tree/system_ext" ] || { echo "the 3a tree is missing: rebuild 3a"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-3a/tree/system" "$P/${TAG}-3a/tree/system_ext" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== SystemUI: OTI resumes after power_off"
D=$SE/priv-app/SystemUI
A=$D/SystemUI.apk
[ "$(md5sum "$A" | cut -d' ' -f1)" = "$SUI_MD5" ] || { echo "SystemUI.apk md5 differs: check patch_systemui_oti.py on this donor"; exit 1; }
python3 -I "$HERE/../module/tools/patch_systemui_oti.py" "$A" "$W/report/SystemUI.apk"
[ "$(md5sum "$W/report/SystemUI.apk" | cut -d' ' -f1)" = "$SUI_NEW" ] || { echo "patched SystemUI.apk md5 differs"; exit 1; }
cat "$W/report/SystemUI.apk" > "$A"
rm -f "$W/report/SystemUI.apk"
rm -rf "$D/oat"
echo "SystemUI.apk $SUI_NEW, oat/ removed"

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
