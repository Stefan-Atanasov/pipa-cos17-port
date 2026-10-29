#!/bin/sh
# Phase 3e: call sharing without echo for the far end (BUGS-TODO 27), on top of 3d (vendor + system_ext). Run as root:
#
#   sudo sh build_beta5_3e.sh
#
# com.oplus.vdc records the pad mic with source VOICE_COMMUNICATION: the HAL uses audio-record-voip = MultiMedia10,
# and the DSP echo canceller reads its reference from AUDIO_REF_EC_UL10 MUX. A shared call is a telephony call
# (MODE_IN_CALL), and the CAF HAL adds "-voip" to the echo-reference path only in MODE_IN_COMMUNICATION, so it set
# only AUDIO_REF_EC_UL1 MUX: no reference, the far end heard itself.
# * vendor/etc/mixer_paths.xml + mixer_paths_overlay_static.xml: module/tools/patch_ec_ref.py copies the UL1 value
#   of each echo-reference path to UL10 (and adds "echo-reference handset" to the base file).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3e.
#
# Input: port-work/${TAG}-3d/{tree/system_ext,img/*.img}. Output: port-work/${TAG}-3e/.
set -eu
TAG=${TAG:-beta5}
STEP=3e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
PREV=$P/${TAG}-3d
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -d "$PREV/tree/system_ext" ] && [ -f "$PREV/img/vendor.img" ] && [ -f "$PREV/img/odm.img" ] || { echo "3d is missing: rebuild 3d"; exit 1; }
free=$(df --output=avail -k "$P" | tail -1)
[ "$free" -gt $((20 * 1024 * 1024)) ] || { echo "less than 20 GB free in $P: a full disk truncates super.img"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$PREV/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext
echo "== vendor: extract (3d vendor.img)"
fsck.erofs --extract="$W/tree/vendor" --xattrs --preserve "$PREV/img/vendor.img"
V=$W/tree/vendor

echo "== 27: echo reference for the VoIP capture in MODE_IN_CALL"
python3 -I "$HERE/../module/tools/patch_ec_ref.py" base "$V/etc/mixer_paths.xml" "$W/report/mixer_paths.xml"
python3 -I "$HERE/../module/tools/patch_ec_ref.py" overlay "$V/etc/mixer_paths_overlay_static.xml" "$W/report/mixer_paths_overlay_static.xml"
for f in mixer_paths.xml mixer_paths_overlay_static.xml; do
    cat "$W/report/$f" > "$V/etc/$f"   # same inode: label kept
    echo "edited  vendor/etc/$f"
done
grep -c 'AUDIO_REF_EC_UL10 MUX' "$V/etc/mixer_paths.xml"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
BP=$SE/etc/build.prop
sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$STEP/" "$BP" > "$W/report/build.prop.new"
cat "$W/report/build.prop.new" > "$BP"
grep "^ro.pipa.port.layer=$STEP\$" "$BP"

echo "== label check"
for t in system_ext vendor; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system_ext, vendor); system, product, odm from 3d"
for t in system_ext vendor; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in system product odm; do cp --reflink=auto "$PREV/img/$p.img" "$W/img/$p.img"; done
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
