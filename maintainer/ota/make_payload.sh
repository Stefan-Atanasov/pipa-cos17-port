#!/bin/sh
# BUGS 193: full A/B OTA payload for update_engine, made from a port.sh build (pipa: Virtual A/B, no compression).
#
#   sh maintainer/ota/make_payload.sh <tag> <boot.img>
#   e.g. sh maintainer/ota/make_payload.sh pt157 ../port-work/kernel/bootimg/boot-walt-hi16.img
#
# Output in port-work/ota/<tag>/: ota-<tag>.zip (payload.bin + payload_properties.txt, stored: update_engine streams
# the payload from it over HTTPS) and ota-<tag>.txt (offset, size and headers for update_engine).
# Partitions: the dynamic ones of the build (system, system_ext, product, vendor, odm), boot (the kernel), and dtbo,
# vendor_boot, vbmeta, vbmeta_system from the release firmware (the same since beta4). FlashLinux.sh keeps boot and dtbo
# of slot A on a keep-data flash, so the payload carries them: then the payload alone defines the target slot.
# Signed with maintainer/ota/keys/pipa-ota.key.pem (private: never commit or share it). The ROM must trust
# maintainer/ota/keys/otacerts.zip (ROM step), else update_engine refuses the payload.
# Needs AOSP otatools (OTATOOLS, default: the copy on the HDD) and dump.erofs. Run time: some minutes (compression).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
COS=$(cd "$HERE/../.." && pwd)
P=$(cd "$COS/.." && pwd)
# FROM=<old tag> (2026-11-25): delta payload from that build (its port-work/<old>/img, or OLD_IMG=<dir>). system, system_ext,
# product, vendor, odm are diffed against the old images; boot is a FULL image (works over any kernel, also the no-KSU
# one); the firmware images are the same in every build. update_engine checks the source hashes: on a device that does
# not hold exactly <old>, the delta fails and the helper falls back to the full payload. Output in
# port-work/ota/<tag>-from-<old>/ (test: test_install.sh <tag>-from-<old>). Payload minor version: OTA_MINOR (8).
[ $# -eq 2 ] || { echo "usage: [FROM=<old tag>] sh make_payload.sh <tag> <boot.img>"; exit 1; }
TAG=$1
BOOT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
O=${OTATOOLS:-/mnt/reference/pipa/tools/otatools-16968706/ota}
IMG=$P/port-work/$TAG/img
FW="$COS/ColorOS17 Port for pipa-beta4-20261017/firmware"
# OTA_KEY: another key, only for the negative test (the ROM must refuse the payload)
KEY=${OTA_KEY:-$HERE/keys/pipa-ota.key.pem}
OUT=$P/port-work/ota/$TAG
NAME=$TAG
if [ -n "${FROM:-}" ]; then
    OLD_IMG=${OLD_IMG:-$P/port-work/$FROM/img}
    for p in system system_ext product vendor odm; do
        [ -s "$OLD_IMG/$p.img" ] || { echo "missing: $OLD_IMG/$p.img (old build images)"; exit 1; }
    done
    NAME=$TAG-from-$FROM
    OUT=$P/port-work/ota/$NAME   # own folder: the full payload's payload_properties.txt stays
fi

for f in "$O/bin/delta_generator" "$KEY" "$BOOT" "$FW/dtbo.img" "$FW/vendor_boot.img" "$FW/vbmeta.img" "$FW/vbmeta_system.img"; do
    [ -s "$f" ] || { echo "missing: $f"; exit 1; }
done
for p in system system_ext product vendor odm; do
    [ -s "$IMG/$p.img" ] || { echo "missing: $IMG/$p.img (port.sh keeps the images in img/)"; exit 1; }
done
# the OS may apply the payload only if its build date is not newer (all port builds have the donor date)
TS=$(dump.erofs --cat --path=/system/build.prop "$IMG/system.img" | sed -n 's/^ro.build.date.utc=//p' | head -1)
[ -n "$TS" ] || { echo "no ro.build.date.utc in system.img"; exit 1; }
mkdir -p "$OUT"
# VABC, method none (as AOSP ota_from_raw_img.py): the A16 libsnapshot refuses legacy VAB (step 9e, BUGS 193).
# same layout as port.sh lpmake (super 9126805504, group qti_dynamic_partitions_a/_b). The group may use only the
# allocatable space (super minus 1 MiB metadata): update_engine refuses 9126805504 (kInstallDeviceOpenError, test 2026-11-25)
cat > "$OUT/dynamic_partitions_info.txt" <<EOF
super_partition_size=9126805504
super_partition_groups=qti_dynamic_partitions
qti_dynamic_partitions_size=9125756928
qti_dynamic_partitions_partition_list=system system_ext product vendor odm
virtual_ab=true
virtual_ab_compression=true
virtual_ab_compression_method=none
EOF
NAMES=system:system_ext:product:vendor:odm:boot:dtbo:vendor_boot:vbmeta:vbmeta_system
NEW="$IMG/system.img:$IMG/system_ext.img:$IMG/product.img:$IMG/vendor.img:$IMG/odm.img:$BOOT"
NEW="$NEW:$FW/dtbo.img:$FW/vendor_boot.img:$FW/vbmeta.img:$FW/vbmeta_system.img"
OLDARG=; MINOR=
if [ -n "${FROM:-}" ]; then
    # empty entries = full operations (boot); firmware = same files (no-op diff)
    OLD="$OLD_IMG/system.img:$OLD_IMG/system_ext.img:$OLD_IMG/product.img:$OLD_IMG/vendor.img:$OLD_IMG/odm.img:"
    OLD="$OLD:$FW/dtbo.img:$FW/vendor_boot.img:$FW/vbmeta.img:$FW/vbmeta_system.img"
    OLDARG=--old_partitions=$OLD
    # a delta needs the payload minor version; the tablet has no update_engine.conf (A16 update_engine: up to 9).
    # 8 = Zucchini diffs (A12+), safe margin
    MINOR=--minor_version=${OTA_MINOR:-8}
fi
export LD_LIBRARY_PATH="$O/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# delta_generator keeps a temp copy of all data (~3.5 GB): never in /tmp (tmpfs, fills up), as port.sh
export TMPDIR="$P/port-work/tmp"; mkdir -p "$TMPDIR"
# OTA_COMPRESS (2026-11-25): none = raw REPLACE (fastest install, ~7.4 GB; the EROFS images are lz4 already),
# zstd = REPLACE_ZSTD (fast to unpack), xz = delta_generator default (pt159: 5.9 GB, ~15 min install, xz unpack on one core)
case "${OTA_COMPRESS:-none}" in
    none) COMP=--disable_replace_compression ;;
    zstd) COMP=--enable_replace_zstd ;;
    xz) COMP= ;;
    *) echo "OTA_COMPRESS: none, zstd or xz"; exit 1 ;;
esac
rm -f "$OUT/payload.bin" "$OUT/payload_properties.txt"
echo "== delta_generator ($NAME, max_timestamp $TS, compression ${OTA_COMPRESS:-none})"
"$O/bin/delta_generator" --out_file="$OUT/payload.bin" --partition_names="$NAMES" --new_partitions="$NEW" \
    --dynamic_partition_info_file="$OUT/dynamic_partitions_info.txt" --major_version=2 --max_timestamp="$TS" \
    --private_key="$KEY" $COMP ${OLDARG:+"$OLDARG"} $MINOR
"$O/bin/delta_generator" --in_file="$OUT/payload.bin" --properties_file="$OUT/payload_properties.txt"

# stored zip (no compression): update_engine reads payload.bin at an offset inside it
python3 -I - "$OUT" "$NAME" <<'PY'
import os, struct, sys, zipfile
out, tag = sys.argv[1], sys.argv[2]
z = os.path.join(out, "ota-%s.zip" % tag)
with zipfile.ZipFile(z, "w", zipfile.ZIP_STORED, allowZip64=True) as f:
    f.write(os.path.join(out, "payload.bin"), "payload.bin")
    f.write(os.path.join(out, "payload_properties.txt"), "payload_properties.txt")
with zipfile.ZipFile(z) as f, open(z, "rb") as raw:
    i = f.getinfo("payload.bin")
    raw.seek(i.header_offset)
    h = raw.read(30)
    off = i.header_offset + 30 + struct.unpack("<H", h[26:28])[0] + struct.unpack("<H", h[28:30])[0]
props = open(os.path.join(out, "payload_properties.txt")).read().strip().split("\n")
with open(os.path.join(out, "ota-%s.txt" % tag), "w") as t:
    t.write("offset=%d\nsize=%d\nheaders=%s\n" % (off, i.file_size, "\\n".join(props)))
print("ota-%s.zip: payload offset %d, size %d" % (tag, off, i.file_size))
PY
md5sum "$OUT/ota-$NAME.zip"
