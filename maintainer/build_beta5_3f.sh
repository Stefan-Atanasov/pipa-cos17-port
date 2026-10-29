#!/bin/sh
# Phase 3f: Game Filter, face crash guard, Bedtime reset, enforcing pipa_port, on top of 3e (system + system_ext).
# Run as root:
#
#   sudo sh build_beta5_3f.sh
#
# * 22 Game Filter / colour enhancement did nothing: OPPO applies them in the panel PQ block (SF transaction 22031 ->
#   IDisplayPanelFeature 35); pipa has no such HAL. system/framework/oplus-services.jar: gamefilter/patch_gamefilter.sh
#   adds com.oplus.vrr.PipaGameFilter (a DisplayTransformManager colour-matrix level, 151) and calls it from
#   OPlusSurfaceFlingerController.setGameFilter(int). Tested live 2026-10-28 (set, and reset when the token dies).
# * 8 face enrollment crash (SIGSEGV in crop_eyes): system_ext/pipa_port/facehal/lib64/libpipa_eyeguard.so
#   (port-module/src/eyeguard.c) + service.sh (LD_PRELOAD).
# * 13 Bedtime reset at each Eye Protect start: system_ext/app/OplusEyeProtect: module/tools/patch_eyeprotect.py (f2 and
#   D1 calls in OplusEyeProtectApp.j() -> nop); oat/ removed. Tested live 2026-10-28 (stock 1 -> 0, patched stays 1).
# * 12 pipa_port SELinux domain enforcing: sepolicy/pipa_port_enforce.py (84 rules from a full permissive boot);
#   compiled on the tablet with secilc and tested live with ksud "enforce pipa_port": no denials.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3f.
#
# Input: port-work/${TAG}-3c/tree/system (3d and 3e did not change system), port-work/${TAG}-3e/{tree/system_ext,img}.
# Output: port-work/${TAG}-3f/.
set -eu
TAG=${TAG:-beta5}
STEP=3f
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
PREV=$P/${TAG}-3e
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
TOOLS=$HERE/../module/tools
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -d "$P/${TAG}-3c/tree/system" ] && [ -d "$PREV/tree/system_ext" ] && [ -f "$PREV/img/vendor.img" ] || { echo "3c system tree or 3e is missing"; exit 1; }
cmp -s "$P/${TAG}-3c/img/system.img" "$PREV/img/system.img" || { echo "3e system.img is not the 3c one: extract system from 3e"; exit 1; }
free=$(df --output=avail -k "$P" | tail -1)
[ "$free" -gt $((20 * 1024 * 1024)) ] || { echo "less than 20 GB free in $P: a full disk truncates super.img"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-3c/tree/system" "$PREV/tree/system_ext" "$W/tree/"
S=$W/tree/system/system
SE=$W/tree/system_ext

echo "== 22: oplus-services.jar Game Filter bridge"
J=$S/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/gamefilter/patch_gamefilter.sh" "$J" "$W/report/oplus-services.jar.new"
cat "$W/report/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
if ls "$S/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then echo "prebuilt oat for oplus-services exists"; exit 1; fi
md5sum "$J"

echo "== 8: face eye-ROI guard"
L=$SE/pipa_port/facehal/lib64
cp "$ROM/pipa_port/facehal/lib64/libpipa_eyeguard.so" "$L/"
chmod 0644 "$L/libpipa_eyeguard.so"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$L/libpipa_facecrop.so")" "$L/libpipa_eyeguard.so"
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
grep -q 'libpipa_eyeguard.so' "$SE/pipa_port/service.sh"
echo "added   system_ext/pipa_port/facehal/lib64/libpipa_eyeguard.so, updated service.sh"

echo "== 13: Eye Protect keeps Bedtime"
E=$SE/app/OplusEyeProtect
python3 -I "$TOOLS/patch_eyeprotect.py" "$E/OplusEyeProtect.apk" "$W/report/OplusEyeProtect.apk"
cat "$W/report/OplusEyeProtect.apk" > "$E/OplusEyeProtect.apk"
rm -rf "$E/oat"
md5sum "$E/OplusEyeProtect.apk"

echo "== 12: pipa_port enforcing"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    if grep -q "(type pipa_port)" "$SE/$f"; then
        python3 -I "$HERE/sepolicy/pipa_port_enforce.py" "$SE/$f"
    else
        echo "skip    $f (no pipa_port block)"
    fi
done
if grep -q "(typepermissive pipa_port)" "$SE/etc/selinux/system_ext_sepolicy.cil"; then echo "still permissive"; exit 1; fi

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

echo "== mkfs (system, system_ext); product, vendor, odm from 3e"
for t in system system_ext; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in product vendor odm; do cp --reflink=auto "$PREV/img/$p.img" "$W/img/$p.img"; done
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
