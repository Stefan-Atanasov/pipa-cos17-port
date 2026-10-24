#!/bin/sh
# Phase 2c: two small ROM fixes on top of beta5-2b (BUGS-TODO.md B9, B6). Run as root after
# build_beta5_2b.sh:
#
#   sudo sh build_beta5_2c.sh
#
# B9 interconnect (call/SMS sharing): bluetooth is denied `find` on ISubsysRadio
#    (tcontext ISubsysService, enforcing). The type is declared in system_ext policy, which already
#    lets nfc, platform_app and others find it; bluetooth is added in the pipa port block.
# B6 native pen lock: ColorOS locks the refresh rate for a stylus when refresh_rate_config.xml's
#    <config> has ipePencilRateId (its own comment: 平板手写笔锁帧120hz, 默认无配置).
#    OplusRefreshRatePolicyImpl.iPEPencilConnectOrPWMMode applies that rate id (3 = 120 Hz) while
#    the pencil counts as connected (global settings_enable_oppo_pencil) and the current rate is
#    90/144/165/185. The Xiaomi pen senses only at 60/120 Hz. power-tune sets the setting while the
#    pen is out of the dock; this build adds the rate id.
#
# Input: port-work/${TAG}-2a/tree/system, port-work/${TAG}-1c/tree/system_ext,
#        port-work/${TAG}-2b/img. Output: port-work/${TAG}-2c/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2b/img
W=$P/${TAG}-2c
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2b.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2a/tree/system" "$P/${TAG}-1c/tree/system_ext" "$W/tree/"

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

echo "== B9 bluetooth -> ISubsysService"
for f in system_ext/etc/selinux/system_ext_sepolicy.cil system_ext/etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$W/tree/$f" ] || { echo "skip    $f (absent)"; continue; }
    grep -q '^(type ISubsysService)' "$W/tree/$f" || { echo "$f: ISubsysService not declared"; exit 1; }
    replace_once $f '(allow domain oplus_vrr_service (service_manager (find)))\n' \
        '(allow domain oplus_vrr_service (service_manager (find)))\n;; B9: call/SMS sharing over Bluetooth needs the virtual modem service\n(allow bluetooth ISubsysService (service_manager (find)))\n'
done

echo "== B6 native stylus refresh lock"
replace_once system/my_product/etc/refresh_rate_config.xml \
    '<config extremeHighEnable="true" maxrefreshsettings="4"' \
    '<config ipePencilRateId="3" extremeHighEnable="true" maxrefreshsettings="4"'

echo "== label check"
for p in system system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$p" > "$W/report/$p.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | wc -l)
    echo "$p: $(wc -l < "$W/report/$p.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system system_ext)"
for p in system system_ext; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$p.img" "$W/tree/$p" > "$W/report/mkfs_$p.log" 2>&1
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
