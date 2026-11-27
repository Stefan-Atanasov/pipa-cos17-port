#!/bin/sh
# Step 9f (2026-11-25, BUGS 175): PUBG main thread on the prime core, as stock. The donor gameopt HAL binds a game's main
# thread to the last (prime) cluster (GameoptIoctl::bindMainThread, frame boost ioctl 0xc028df01); the port's gameopt
# shim (step 4r, halshims.jar) now does the same with the tool fbgctl (maintainer/fbgctl), once per game lease, reset
# with the lease. Measured pt161 + live bind 2026-11-25: UEGameThread on cpu7 0 % -> 85 % of its run time (lobby).
# SELinux (maintainer/sepolicy/rules_9f_system_ext.cil): pipa_port may ioctl 0xdf01 on proc_frame_boost_sys_ctrl.
# Host secilc 2026-11-25 (otatools 16968706): exit 0.
#NEEDS: "$ROM/pipa_port/fbgctl" "$ROM/pipa_port/halshims.jar" "$HERE/sepolicy/rules_9f_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=9f
SE=$T/system_ext
file "$ROM/pipa_port/fbgctl" | grep -q 'ARM aarch64.*statically linked' || die "fbgctl: build it (sh maintainer/fbgctl/build.sh)"
install -o 0 -g 0 -m 755 "$ROM/pipa_port/fbgctl" "$SE/pipa_port/fbgctl"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$SE/pipa_port/fbgctl"
need_grep '/system_ext/pipa_port/fbgctl' "$SE/pipa_port/halshims.jar"
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 9f" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_9f_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 9f" "$SE/etc/selinux/$f"
done
echo "fbgctl, gameopt shim bind main thread, frame boost ioctl rule"
set_layer "$STEP"
