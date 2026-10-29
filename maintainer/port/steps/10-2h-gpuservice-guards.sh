#!/bin/sh
# Phase 2h: null guards in OPPO's gpuservice extension, on top of 2g (system_ext only).
#
# GpuServiceExtImpl::onTransact (system_ext/lib64/libgpuserviceextimpl.so) forwards six binder calls to its
# PreCacheService without checking that it exists yet. It is created only after GpuMem::initialize(), which waits
# 30 s when the kernel has no gpu_mem tracepoint (our own E404 kernel; the stock joeyzhu kernel has it). Every app
# that starts EGL in that window crashed gpuservice (3-5 tombstones per boot). maintainer/patch_gpuserviceext.py
# makes each call return 0 while the service is missing; nothing changes once it exists, so the stock kernel
# behaves as before. Tested live on E404 (bind mount): 6 app starts in the window, no crash.
#
# Old layer script: build_beta5_2h.sh
#NEEDS: "$HERE/patch_gpuserviceext.py"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext

echo "== gpuservice extension null guards"
F=$SE/lib64/libgpuserviceextimpl.so
python3 -I "$HERE/patch_gpuserviceext.py" "$F" "$W/libgpuserviceextimpl.so"
cat "$W/libgpuserviceextimpl.so" > "$F"   # in place: owner, mode and SELinux label stay
rm -f "$W/libgpuserviceextimpl.so"
md5sum "$F"

