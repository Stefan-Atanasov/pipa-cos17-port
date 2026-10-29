#!/bin/sh
# Phase 3c: interconnect network/call/SMS sharing reaches the phone (BUGS-TODO B9), on top of 3b (system +
# system_ext). Run as root:
#
#   sudo sh build_beta5_3c.sh
#
# * system_ext sepolicy: com.oplus.subsys (system_app) was denied binder call to commcenterd (hal_radio_default,
#   IDmtpService), so its DMTP client never registered (forbid bit 128, no virtual comm link). Four rules in the
#   pipa block: system_app <-> hal_radio_default binder call/transfer, fd use, find hal_radio_service.
# * system_ext/etc/init/pipa_port.rc: persist.radio.multisim.config=dsds and persist.vendor.radio.virtualcomm=1 at
#   post-fs-data (the OPPO odm sets them; pipa's odm does not). With one phone slot com.android.phone crashed in a
#   loop (OplusVmServiceStateOberser.updateVoiceRegstateResult, index 1 of length 1).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3c (early.sh clears the package cache).
# Still missing for network sharing: the OPPO kernel netdev "ovnet" (ip link add ovnet0 type ovnet bind p2p0 ...).
#
# Input: port-work/${TAG}-3b/tree/system + system_ext, port-work/${TAG}-2t/img (product, vendor, odm).
# Output: port-work/${TAG}-3c/.
set -eu
TAG=${TAG:-beta5}
STEP=3c
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2t/img
W=$P/${TAG}-$STEP
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2t.sh first"; exit 1; }
[ -d "$P/${TAG}-3b/tree/system" ] && [ -d "$P/${TAG}-3b/tree/system_ext" ] || { echo "the 3b tree is missing: rebuild 3b"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-3b/tree/system" "$P/${TAG}-3b/tree/system_ext" "$W/tree/"
S=$W/tree/system
SE=$W/tree/system_ext

echo "== B9: pipa_port.rc (dual virtual SIM slots)"
cat "$ROM/pipa_port.rc" > "$SE/etc/init/pipa_port.rc"
grep -q '^    setprop persist.radio.multisim.config dsds$' "$SE/etc/init/pipa_port.rc"
echo "updated system_ext/etc/init/pipa_port.rc"

echo "== B9: system_app <-> commcenterd (DMTP)"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    python3 -I - "$SE/$f" <<'PY'
import sys
p = sys.argv[1]
a = '(allow bluetooth ISubsysService (service_manager (find)))\n'
b = (';; B9 (3c): com.oplus.subsys (system_app) registers its DMTP client at commcenterd (hal_radio_default)\n'
     '(allow system_app hal_radio_default (binder (call transfer)))\n'
     '(allow hal_radio_default system_app (binder (call transfer)))\n'
     '(allow hal_radio_default system_app (fd (use)))\n'
     '(allow system_app hal_radio_service (service_manager (find)))\n')
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
