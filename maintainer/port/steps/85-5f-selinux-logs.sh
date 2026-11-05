#!/bin/sh
# Phase 5f: SELinux rules from a full pt41 capture, and less log spam (user 2026-11-04: clean logs, smoothness).
#
# * system_ext/etc/selinux/system_ext_sepolicy{,_debug}.cil + sepolicy/rules_5f_system_ext.cil:
#   UI First hints for SurfaceFlinger, bootanim and apps (im_flag_app, binder ux_flag), f2fs GC policy nodes for init
#   and system_server (OplusStorageManagerFeature: EACCES 69 times a minute at idle), read-only prop access of
#   platform daemons, HeyTap accessory sysfs/cgroup polls; dontaudit for debuglog, nandswap and boringssl probes.
# * vendor/etc/selinux/vendor_sepolicy.cil + sepolicy/rules_5f_vendor.cil: ueventd firmware dir, init USB supply
#   nodes; dontaudit for diag, thermald HBM node, Qualcomm init shell and persist mount probes.
#   Both compiled on the tablet with secilc (the init file set, exit 0) before the build.
# * my_stock/priv-app/FindMyPhone is NOT removed (pt57): the setup wizard needs its provider (see below). BUGS 67:
#   it cannot work on pipa (no OPPO RPMB/TEE storage) and retries at boot (~200 error lines).
#NEEDS: "$HERE/sepolicy/rules_5f_system_ext.cil" "$HERE/sepolicy/rules_5f_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=5f

SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 5f" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_5f_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5f" "$SE/system_ext_sepolicy.cil"

CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 5f" "$CIL"
need_grep "^(type vendor_diag_device)" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_5f_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

# FindMyPhone stays (pt57, 2026-11-05): the setup wizard com.coloros.bootreg (GuidePage.initDeferredGuideWork)
# registers an observer on com.coloros.findmyphone.provider.SharedProvider and crashes in a loop without it
# = grey screen after a clean flash (beta7). A dirty flash skips the setup wizard.
D=$T/system/my_stock/priv-app/FindMyPhone
[ -f "$D/FindMyPhone.apk" ] || die "no $D/FindMyPhone.apk (the setup wizard needs its provider)"

set_layer "$STEP"
