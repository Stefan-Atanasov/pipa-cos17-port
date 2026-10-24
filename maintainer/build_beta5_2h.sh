#!/bin/sh
# Phase 2h: null guards in OPPO's gpuservice extension, on top of 2g (system_ext only). Run as root:
#
#   sudo sh build_beta5_2h.sh
#
# GpuServiceExtImpl::onTransact (system_ext/lib64/libgpuserviceextimpl.so) forwards six binder calls to its
# PreCacheService without checking that it exists yet. It is created only after GpuMem::initialize(), which waits
# 30 s when the kernel has no gpu_mem tracepoint (our own E404 kernel; the stock joeyzhu kernel has it). Every app
# that starts EGL in that window crashed gpuservice (3-5 tombstones per boot). maintainer/patch_gpuserviceext.py
# makes each call return 0 while the service is missing; nothing changes once it exists, so the stock kernel
# behaves as before. Tested live on E404 (bind mount): 6 app starts in the window, no crash.
#
# Input: port-work/${TAG}-2g/tree/{system,system_ext}, port-work/${TAG}-2g/img. Output: port-work/${TAG}-2h/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2g, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2g/img
W=$P/${TAG}-2h
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
LABEL=u:object_r:system_file:s0
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2g.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2g/tree/system" "$P/${TAG}-2g/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext

echo "== gpuservice extension null guards"
F=$SE/lib64/libgpuserviceextimpl.so
python3 -I "$HERE/patch_gpuserviceext.py" "$F" "$W/libgpuserviceextimpl.so"
cat "$W/libgpuserviceextimpl.so" > "$F"   # in place: owner, mode and SELinux label stay
rm -f "$W/libgpuserviceextimpl.so"
md5sum "$F"

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
