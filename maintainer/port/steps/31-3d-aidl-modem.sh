#!/bin/sh
# Phase 3d: call sharing over interconnect (BUGS-TODO B9): the virtual modem speaks AIDL, on top of 3c (odm +
# system_ext).
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
# Old layer script: build_beta5_3d.sh
#NEEDS: "$P/donor-c06-vendor/odm.img" "$P/donor-c06-vendor/vendor.img" "$HERE/aidl-modem/network_manifest.xml" "$HERE/aidl-modem/odm_service_contexts.add"
set -eu
. "$PORT/lib.sh"
STEP=3d
C06_VENDOR=$P/donor-c06-vendor      # C.06 vendor.img and odm.img (the original script called this DONOR)
[ -f "$C06_VENDOR/odm.img" ] && [ -f "$C06_VENDOR/vendor.img" ] || die "C.06 vendor/odm images missing: $C06_VENDOR"

SE=$T/system_ext
echo "== odm: C.06 odm (the port odm is already in $T/odm)"
rm -rf "$W/donor"; mkdir -p "$W/donor"
fsck.erofs --extract="$W/donor/odm" "$C06_VENDOR/odm.img"
dump.erofs --cat --path=/lib64/libprotobuf-cpp-lite-21.12.so "$C06_VENDOR/vendor.img" > "$W/donor/libprotobuf-cpp-lite-21.12.so"
O=$T/odm
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
[ "$(grep -c 'setenv LD_LIBRARY_PATH /odm/lib64/aidl' "$O/etc/init/virtual_daemon.rc")" = 2 ] || die "virtual_daemon.rc: expected 2 LD_LIBRARY_PATH lines"
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
set_layer "$STEP"

