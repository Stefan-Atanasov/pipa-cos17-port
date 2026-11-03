#!/bin/sh
# Phase 4r: own-code OPPO HAL shims in one host (system_ext).
#
# halshims.jar (maintainer/halshims, own Java code, build.sh) serves, in ONE app_process (one ART runtime; review fixes 2026-11-03: ux_state parse, guarded handler,
# lease rules, touch fallback):
#   gameopt  vendor.oplus.hardware.gameopt.IGameOptHalService/default (V2): game key threads, GL and critical
#            threads get sched_assist UX (ux_task) as on ColorOS; bounded and reset on background, game switch,
#            process death, 30 min, shim stop. oiface and SurfaceFlinger find a real HAL.
#   panel    vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default (V1): backlight values, probe ids
#            "not supported", accepted ids kept, -1 for the rest (donor behaviour for an unknown id).
#   misc     vendor.oplus.hardware.misc.IOplusMisc/default (V1): read-only, OPPO node flags only where pipa has the
#            same node; ends the HIDL getService(true) fallback.
#   touch    the 4o touch shim (same code, built into this jar): one app_process less. Its service name keeps the
#            4o label (oplus_absent_service); service.sh skips the separate 4o host.
# Static analysis: notes/cloud/GAMEOPT.md, GAMEOPT-SHIM.md, DISPLAY-HALS.md, MISC-SENSOR.md. pipa_port service.sh
# starts the host and the registrar (HAL_SHIMS in config.prop). One service type for each name
# (maintainer/halshims/halshims.cil).
#NEEDS: "$ROM/pipa_port/halshims.jar" "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop" "$HERE/halshims/halshims.cil"
set -eu
. "$PORT/lib.sh"
STEP=4r
SE=$T/system_ext

# jar: same owner, mode and SELinux label as the charger jar next to it
install -o 0 -g 0 -m 644 "$ROM/pipa_port/halshims.jar" "$SE/pipa_port/halshims.jar"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$SE/pipa_port/chargershim.jar")" "$SE/pipa_port/halshims.jar"
need_grep 'pipa/hal/GameOptService' "$SE/pipa_port/halshims.jar"
need_grep 'pipa/touch/TouchService' "$SE/pipa_port/halshims.jar"

echo "== SELinux: one service type for each shim"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    if grep -q 'pipa_hal_panel_service' "$SE/$f"; then echo "$f: already patched"; exit 1; fi
    cat "$HERE/halshims/halshims.cil" >> "$SE/$f"   # in place: owner, mode and label stay
    echo "edited  system_ext/$f"
done
C=$SE/etc/selinux/system_ext_service_contexts
# A name may have only ONE label in all service_contexts files together (system, system_ext, product, vendor, odm):
# two different labels stop servicemanager at boot (pt29). gameopt is labelled oplus_absent_service by the pipa
# vendor, so it gets no line here; the check covers every service_contexts file of the tree.
CTX=$(find "$T" -name '*service_contexts' -type f)
[ -n "$CTX" ] || die "no service_contexts files in the tree"
need_grep 'vendor.oplus.hardware.gameopt.IGameOptHalService/default[[:space:]]*u:object_r:oplus_absent_service:s0' $(echo "$CTX" | grep vendor_service_contexts)
for n in displaypanelfeature.IDisplayPanelFeature misc.IOplusMisc; do
    for f in $CTX; do forbid_grep "vendor.oplus.hardware.$n/default" "$f"; done
done
{
    printf 'vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default u:object_r:pipa_hal_panel_service:s0\n'
    printf 'vendor.oplus.hardware.misc.IOplusMisc/default u:object_r:pipa_hal_misc_service:s0\n'
} >> "$C"   # same inode

cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'pipa.hal.HalHost' "$SE/pipa_port/service.sh"
cat "$ROM/pipa_port/config.prop" > "$SE/pipa_port/config.prop"
need_grep '^HAL_SHIMS=' "$SE/pipa_port/config.prop"
set_layer "$STEP"
