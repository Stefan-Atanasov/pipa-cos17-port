#!/bin/sh
# Phase 4x: OPPO storage maintenance without the parts that cannot work on pipa (cloud task notes/cloud/DEFRAG.md;
# product only).
#
# StorageManagerService.runIdleMaint starts oplus_defrag (lazy AIDL, domain installd) for three jobs:
# * file defrag (F2FS_IOC_DEFRAGMENT): the pipa kernel has it -> stays on.
# * compress/dedup scan: it hashes files (md5) into dedup_scan_0.db, but the dedup ioctls (f2fs 0xf5 100..107) are
#   OPPO-only and absent in the pipa kernel -> I/O and battery for nothing.
# * Turbo Pocket: needs the OPPO UFS driver (ufstp sysfs) and /proc/devinfo/ufs; pipa has neither.
# * product/etc/build.prop: persist.sys.oplus.disableCompressDedup=1, persist.sys.oplus.disableTurboPocket=1 (a
#   persist default: used while the user has not set the prop). Tested live 2026-11-03 (setprop + sm idle-maint run):
#   "enableDefrag:true enableScan:false enableTurboPocket:false", oplus_defrag starts and runs defragFiles.
set -eu
. "$PORT/lib.sh"

BP=$T/product/etc/build.prop
echo "== storage idle maintenance: dedup scan and Turbo Pocket off"
for p in persist.sys.oplus.disableCompressDedup persist.sys.oplus.disableTurboPocket; do
    if grep -q "^$p=" "$BP"; then echo "product build.prop already sets $p"; exit 1; fi
done
{ cat "$BP"; printf '%s\n' "# pipa port 4x: no dedup scan / Turbo Pocket (OPPO-only f2fs ioctls and UFS driver; file defrag stays)" \
    "persist.sys.oplus.disableCompressDedup=1" "persist.sys.oplus.disableTurboPocket=1"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label kept
tail -3 "$BP"
