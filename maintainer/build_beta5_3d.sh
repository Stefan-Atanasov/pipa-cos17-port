#!/bin/sh
# Phase 3d: call sharing over interconnect (BUGS-TODO B9): the virtual modem speaks AIDL, on top of 3c (odm +
# system_ext). Run as root:
#
#   sudo sh build_beta5_3d.sh
#
# The C.06 IMS app (system_ext/priv-app/ims, process com.qti.phone) is AIDL-only: it looks for
# vendor.qti.hardware.radio.ims.IImsRadio/imsradio0 and logged "ImsSenderRxr : ImsRadio HAL is not available", so a
# call that reached the virtual modem never rang on the pad. The port odm had beta4's HIDL virtual modem.
# * odm/lib64: C.06 lib-virtual-modem-radio-aidl.so (dlopens /odm/lib64/lib-virtual-modem-qti-ims-aidl.so) and the
#   new NDK interface libs (radio V3, ims V7, qtiradioconfig V2), libprotobuf-cpp-lite-21.12.so from the C.06 vendor.
# * odm/lib64/aidl: the C.06 builds of 10 libs that the port odm also has under the same soname (commcenterd and
#   pipa_subsys keep the port builds); virtual_daemon.rc sets LD_LIBRARY_PATH for the two virtual RIL daemons.
# * odm VINTF network_manifest.xml: AIDL radio V3 (vircomm1/2), ims V7, qtiradioconfig V2 instead of the HIDL
#   IRadio 1.5 / IImsRadio 1.7 entries; odm_service_contexts: the 12 AIDL radio names as hal_radio_service.
# * system_ext sepolicy: init noatsecure to hal_radio_default (else AT_SECURE drops LD_LIBRARY_PATH).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3d.
# Plan and dependency closure: notes/aidl-virtual-modem/ (PLAN-files.txt, closure.tsv).
#
# Input: port-work/${TAG}-3c/{tree/system_ext,img/system.img}, port-work/${TAG}-2t/img (product, vendor, odm),
#        port-work/donor-c06-vendor/{odm,vendor}.img. Output: port-work/${TAG}-3d/.
set -eu
TAG=${TAG:-beta5}
STEP=3d
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
DONOR=$P/donor-c06-vendor
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-3c/tree/system_ext" ] && [ -f "$P/${TAG}-3c/img/system.img" ] || { echo "3c is missing: rebuild 3c"; exit 1; }
[ -f "$DONOR/odm.img" ] && [ -f "$DONOR/vendor.img" ] || { echo "C.06 vendor/odm images missing: $DONOR"; exit 1; }
free=$(df --output=avail -k "$P" | tail -1)
[ "$free" -gt $((12 * 1024 * 1024)) ] || { echo "less than 12 GB free in $P: a full disk truncates super.img"; exit 1; }

rm -rf "$W/tree" "$W/donor"; mkdir -p "$W/tree" "$W/img" "$W/report" "$W/donor"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-3c/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext
echo "== odm: extract (2t odm.img), C.06 odm"
fsck.erofs --extract="$W/tree/odm" --xattrs --preserve "$IMGSRC/odm.img"
fsck.erofs --extract="$W/donor/odm" "$DONOR/odm.img"
dump.erofs --cat --path=/lib64/libprotobuf-cpp-lite-21.12.so "$DONOR/vendor.img" > "$W/donor/libprotobuf-cpp-lite-21.12.so"
O=$W/tree/odm
D=$W/donor/odm

add() {   # <source> <odm path> <selinux type>
    [ -e "$O/$2" ] && { echo "already in odm: $2"; exit 1; }
    [ -s "$1" ] || { echo "missing source: $1"; exit 1; }
    cp "$1" "$O/$2"
    chown 0:0 "$O/$2"; chmod 644 "$O/$2"
    setfattr -n security.selinux -v "u:object_r:$3:s0" "$O/$2"
    echo "added   odm/$2"
}
echo "== AIDL virtual modem libs"
for l in lib-virtual-modem-radio-aidl.so lib-virtual-modem-qti-ims-aidl.so \
         android.hardware.radio-V3-ndk.so android.hardware.radio.config-V3-ndk.so android.hardware.radio.data-V3-ndk.so \
         android.hardware.radio.messaging-V3-ndk.so android.hardware.radio.modem-V3-ndk.so \
         android.hardware.radio.network-V3-ndk.so android.hardware.radio.sim-V3-ndk.so \
         android.hardware.radio.voice-V3-ndk.so vendor.qti.hardware.radio.ims-V7-ndk.so \
         vendor.qti.hardware.radio.qtiradioconfig-V2-ndk.so; do
    add "$D/lib64/$l" "lib64/$l" vendor_file
done
add "$W/donor/libprotobuf-cpp-lite-21.12.so" lib64/libprotobuf-cpp-lite-21.12.so vendor_file
mkdir "$O/lib64/aidl"
chown 0:2000 "$O/lib64/aidl"; chmod 755 "$O/lib64/aidl"
setfattr -n security.selinux -v u:object_r:vendor_file:s0 "$O/lib64/aidl"
for l in libcommcenterfw.so libcommcenterutils.so libdmtpclient.so libdmtp-protos-lite.so libmindroid-framework.so \
         libmindroid-app.so libsubsys-utils.so lib-virtual-modem-api.so lib-virtual-modem-protos.so \
         vendor.oplus.hardware.communicationcenter-V2-ndk.so; do
    [ -f "$O/lib64/$l" ] || { echo "port odm has no $l: the plan assumed a soname collision"; exit 1; }
    add "$D/lib64/$l" "lib64/aidl/$l" vendor_file
done

edit() {   # <odm path> <python body on s>; same inode, labels kept
    python3 -I - "$O/$1" "$2" <<'PY'
import sys
p, body = sys.argv[1:]
s = open(p, encoding='utf-8').read()
env = {'s': s}
exec(body, env)
with open(p, 'r+', encoding='utf-8') as f:
    f.write(env['s']); f.truncate()
PY
    echo "edited  odm/$1"
}
echo "== virtual_daemon.rc: AIDL radio lib, private lib dir"
edit etc/init/virtual_daemon.rc '
old = "/odm/bin/hw/subsys_daemon -l /odm/lib64/lib-virtual-modem-radio.so -i "
assert s.count(old) == 2, "virtual_daemon.rc: expected 2 virtual-ril-daemon lines"
s = s.replace(old, "/odm/bin/hw/subsys_daemon -l /odm/lib64/lib-virtual-modem-radio-aidl.so -i ")
cap = "    capabilities BLOCK_SUSPEND NET_ADMIN NET_RAW\n"
assert s.count(cap) == 2, "virtual_daemon.rc: expected 2 capabilities lines"
s = s.replace(cap, cap + "    setenv LD_LIBRARY_PATH /odm/lib64/aidl\n")
'
grep -c 'setenv LD_LIBRARY_PATH /odm/lib64/aidl' "$O/etc/init/virtual_daemon.rc"
echo "== VINTF network_manifest.xml"
grep -q '<instance>vircommslot1</instance>' "$O/etc/vintf/manifest/network_manifest.xml" || { echo "network_manifest.xml is not the beta4 one"; exit 1; }
cat "$HERE/aidl-modem/network_manifest.xml" > "$O/etc/vintf/manifest/network_manifest.xml"
echo "== odm_service_contexts"
if grep -q 'IRadioModem/vircomm1' "$O/etc/selinux/odm_service_contexts"; then echo "already labelled"; exit 1; fi
cat "$HERE/aidl-modem/odm_service_contexts.add" >> "$O/etc/selinux/odm_service_contexts"

echo "== system_ext sepolicy: init noatsecure -> hal_radio_default"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    python3 -I - "$SE/$f" <<'PY'
import sys
p = sys.argv[1]
a = '(allow system_app hal_radio_service (service_manager (find)))\n'
b = (';; B9 (3d): keep LD_LIBRARY_PATH for the AIDL virtual RIL daemons (no AT_SECURE)\n'
     '(allow init hal_radio_default (process (noatsecure)))\n')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
if s.count(a) != 1:
    sys.exit(f'{p}: anchor found {s.count(a)} times, expected 1')
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s.replace(a, a + b)); f.truncate()
PY
    echo "edited  system_ext/$f"
done

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
BP=$SE/etc/build.prop
sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$STEP/" "$BP" > "$W/report/build.prop.new"
cat "$W/report/build.prop.new" > "$BP"
grep "^ro.pipa.port.layer=$STEP\$" "$BP"

echo "== label check"
for t in system_ext odm; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system_ext, odm); system from 3c"
for t in system_ext odm; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
cp --reflink=auto "$P/${TAG}-3c/img/system.img" "$W/img/system.img"
for p in product vendor; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
