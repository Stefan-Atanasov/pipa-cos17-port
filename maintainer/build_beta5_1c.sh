#!/bin/sh
# Phase 1c: three pipa_core runtime tasks moved into the ROM (PHASE2-ROM-INTEGRATION.md A1, A2, A4).
# Layered on the phase 1 build; run as root after build_beta5_baked.sh (and flash only after that
# image has booted, so each flash tests one step):
#
#   sudo sh build_beta5_1c.sh                    A1 + A2
#   sudo DROP_FACEUNLOCK=1 sh build_beta5_1c.sh  + A4 (only after confirming on the device that
#                                                /data/system/facehal_socket never exists)
#
# A1 system_ext loc_sys_service.rc: don't start the GNSS service (pipa has no GNSS hardware; it
#    retries ILocAidlGnss once a second, ~2.4 log lines/s). pipa_core still stops it; harmless.
# A2 vendor ueventd.rc: pen charger sysfs nodes owned by system, 0664, set by ueventd itself instead
#    of pipa_core's post-fs-data chown/chmod. pipa_core's chown then changes nothing.
# A4 system/app/FaceUnlock: the legacy socket face client (com.pipa.faceunlock, R4). The facehal-rs
#    AIDL HAL replaced it; the power-tune module only keeps it disabled.
#
# Input: port-work/${TAG}-baked/{tree,img}. Output: port-work/${TAG}-1c/{tree,img,report}.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
DROP_FACEUNLOCK=${DROP_FACEUNLOCK:-0}
SRC=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-baked
W=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/${TAG}-1c
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$SRC/img/super.img" ] || { echo "run build_beta5_baked.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$SRC/tree/system" "$SRC/tree/system_ext" "$SRC/tree/vendor" "$W/tree/"

replace_once() {
    python3 -I - "$W/tree/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]
old, new = old.encode().decode('unicode_escape'), new.encode().decode('unicode_escape')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != 1:
    sys.exit(f"{p}: anchor found {n} times, expected 1")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s.replace(old, new)); f.truncate()
PY
    [ $? = 0 ] || exit 1
    echo "edited  $1"
}

echo "== A1 GNSS service"
replace_once system_ext/etc/init/loc_sys_service.rc \
    'on early-boot\n    start loc_sys_service\n' \
    '# pipa port: no GNSS hardware; the service retries ILocAidlGnss once a second\non early-boot\n#    start loc_sys_service\n'

echo "== A2 pen sysfs permissions"
grep -q 'fuda' "$W/tree/vendor/etc/ueventd.rc" && { echo "ueventd.rc already mentions fuda"; exit 1; }
python3 -I - "$W/tree/vendor/etc/ueventd.rc" <<'PY'
import sys
p = sys.argv[1]
add = """
# pipa port: pen wireless charger nodes written by system_server (was a chown in pipa_core)
/sys/class/power_supply/fuda      reverse_chg_mode        0664    system    system
/sys/class/power_supply/fuda      reverse_pen_soc         0664    system    system
/sys/class/power_supply/wireless  pen_mac                 0664    system    system
/sys/class/power_supply/wireless  reverse_pen_chg_state   0664    system    system
"""
with open(p, 'a', encoding='utf-8') as f:   # same inode: label kept
    f.write(add)
PY
echo "edited  vendor/etc/ueventd.rc"

PARTS="system_ext vendor"
if [ "$DROP_FACEUNLOCK" = 1 ]; then
    echo "== A4 drop FaceUnlock"
    [ -d "$W/tree/system/system/app/FaceUnlock" ] || { echo "FaceUnlock not found"; exit 1; }
    rm -rf "$W/tree/system/system/app/FaceUnlock"
    PARTS="system system_ext vendor"
fi

echo "== label check"
for p in $PARTS; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$p" > "$W/report/$p.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | wc -l)
    echo "$p: $(wc -l < "$W/report/$p.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs ($PARTS)"
for p in system system_ext product vendor odm; do
    case " $PARTS " in
        *" $p "*) mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$p.img" "$W/tree/$p" > "$W/report/mkfs_$p.log" 2>&1 ;;
        *) cp --reflink=auto "$SRC/img/$p.img" "$W/img/$p.img" ;;
    esac
done
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
