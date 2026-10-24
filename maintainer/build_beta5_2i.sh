#!/bin/sh
# Phase 2i: SELinux labels and rules for OPPO's UI First proc nodes, on top of 2h (system_ext only). Run as root:
#
#   sudo sh build_beta5_2i.sh
#
# Our WALT kernel (branch oppo) provides ColorOS 17's UI First interface: /proc/oplus_scheduler/sched_assist/
# {ux_task,ux_task_app,im_flag,im_flag_app}, /proc/oplus_frame_boost/sys_ctrl, /proc/sys/fbg/*. Their labels and
# rules are in OPPO's vendor policy, which we do not ship (pipa vendor), so system_server and apps get EACCES on
# plain `proc`. uifirst-policy/sa_block.cil (generated from the donor vendor rules, see uifirst-policy/README.md)
# declares the types, labels the nodes and grants the donor's access. Harmless on kernels without these nodes.
#
# Input: port-work/${TAG}-2h/tree/{system,system_ext}, port-work/${TAG}-2h/img. Output: port-work/${TAG}-2i/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2h, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2h/img
W=$P/${TAG}-2i
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2h.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2h/tree/system" "$P/${TAG}-2h/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== SELinux: UI First proc nodes"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    if grep -q 'oplus_scheduler_sched_assist_proc' "$SE/$f"; then echo "$f: already patched"; exit 1; fi
    # in place (cat >>): owner, mode and SELinux label stay
    cat "$HERE/uifirst-policy/sa_block.cil" >> "$SE/$f"
    echo "edited  system_ext/$f (+$(wc -l < "$HERE/uifirst-policy/sa_block.cil") lines)"
done

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
