#!/bin/sh
# Phase 2f: fixes for the first beta5-2e boot, on top of 2e (system_ext only). Run as root:
#
#   sudo sh build_beta5_2f.sh
#
# * pen_keys.sh: `input keyevent` ran with the getevent pipe as stdin; `cmd` hands the caller's
#   stdin to system_server over binder, system_server may not use a pipe labelled pipa_port, and the
#   call died with "Failed transaction (2147483646)" (nothing in the AVC trace: dontaudit). The
#   back-button screenshot did nothing. Every action now gets plain /dev/null streams.
# * service.sh: the "pen connected" message to IPeManager is sent again 10 s and 40 s after the
#   pen connects (the one at boot was sometimes ignored: Settings showed the stylus as not
#   connected until the message was sent again).
# The pipa_port domain is still PERMISSIVE; the enforcing rules come with a boot trace in a later build.
#
# Input: port-work/${TAG}-2e/tree/{system,system_ext}, port-work/${TAG}-2e/img. Output: port-work/${TAG}-2f/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2e/img
W=$P/${TAG}-2f
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
LABEL=u:object_r:system_file:s0
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2e.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2e/tree/system" "$P/${TAG}-2e/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== pipa_port scripts"
for f in pen_keys.sh service.sh; do
    cmp -s "$ROM/pipa_port/$f" "$SE/pipa_port/$f" && { echo "unchanged $f"; continue; }
    install -o 0 -g 0 -m 644 "$ROM/pipa_port/$f" "$SE/pipa_port/$f"
    setfattr -n security.selinux -v "$LABEL" "$SE/pipa_port/$f"
    echo "updated  system_ext/pipa_port/$f ($(md5sum < "$ROM/pipa_port/$f" | cut -c1-8))"
done
grep -c '</dev/null >/dev/null 2>&1' "$SE/pipa_port/pen_keys.sh"
grep -c 'resend' "$SE/pipa_port/service.sh"

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$SE" > "$W/report/system_ext.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/system_ext.tsv" | wc -l)
echo "system_ext: $(wc -l < "$W/report/system_ext.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (system_ext)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system_ext.img" "$SE" > "$W/report/mkfs_system_ext.log" 2>&1
for p in system product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
