#!/bin/sh
# Phase 8i (2026-11-20, BUGS 156): Qualcomm SurfaceFlinger extension on, as stock HyperOS. Replaces 7t.
#
# * Stock HyperOS vendor/build.prop has vendor.display.enable_display_extensions=1. The beta4 vendor does not, so the
#   donor SurfaceFlinger loaded QtiNullSurfaceFlingerExtension (log "Enabling QtiNullSurfaceFlingerExtension in
#   QSSI"): qtiCanAllocateHwcDisplayIdForVDS was a "return false" stub (pt136 uprobe on processDisplayAdded), so 6h's
#   vds_allow_hwc=1 ("HWC for WFD only") did nothing. 7t then set debug.sf.enable_hwc_vds=1 (AOSP init:
#   enableHalVirtualDisplays for every virtual display): Miracast clean, but Gemini Live screen share black and slow.
# * With the extension: log "Allow HWC for WFD"; the wfdservice sink (consumer usage PRIVATE_WFD | VIDEO_ENCODER) gets
#   the HWC virtual display, all other virtual displays (screenrecord, Gemini, cast apps) stay on the GPU.
#   Live test pt136 2026-11-20: Miracast to Windows clean, Gemini screen share works and is smooth (user).
# * Feature values as stock HyperOS vendor/build.prop. Before, they did nothing (no extension); now they apply:
#   use_smooth_motion 1 -> 0 (beta4 took 1 from AOSPA; stock 0: no SmoMo video refresh matching),
#   disable_dynamic_sf_idle=1 (stock). Idle refresh unchanged in the live test (120 Hz on touch, 60 Hz at idle).
#   enable_advanced_sf_phase_offset=1 and enable_allow_idle_fallback=1 are already the stock values. The log line
#   "Enable Work Durations" follows the phase offset flag only; use_phase_offsets_as_durations stays unset.
# * system build.prop: debug.sf.enable_hwc_vds 1 -> 0 (stock HyperOS and donor value; undoes 7t).
set -eu
. "$PORT/lib.sh"
STEP=8i

VB=$T/vendor/build.prop
[ -f "$VB" ] || die "no $VB"
for f in $(find "$T" -maxdepth 4 -name build.prop -type f); do
    forbid_grep '^vendor.display.enable_display_extensions=' "$f"
    forbid_grep '^vendor.display.disable_dynamic_sf_idle=' "$f"
done
need_grep '^vendor.display.use_smooth_motion=1$' "$VB"
awk '$0=="vendor.display.use_smooth_motion=1"{
        print "# pipa port 8i (BUGS 156): Qualcomm SurfaceFlinger extension, values as stock HyperOS"
        print "vendor.display.enable_display_extensions=1"
        print "vendor.display.use_smooth_motion=0"
        print "vendor.display.disable_dynamic_sf_idle=1"
        next } {print}' "$VB" > "$R/vendor.build.prop.8i"
cat "$R/vendor.build.prop.8i" > "$VB"   # same inode: label, owner and mode kept
rm -f "$R/vendor.build.prop.8i"
need_grep '^vendor.display.enable_display_extensions=1$' "$VB"
need_grep '^vendor.display.use_smooth_motion=0$' "$VB"
forbid_grep '^vendor.display.use_smooth_motion=1$' "$VB"
grep -n -A3 'pipa port 8i' "$VB"

BP=$T/system/system/build.prop
[ -f "$BP" ] || BP=$T/system/build.prop
[ -f "$BP" ] || die "no system build.prop"
need_grep '^debug.sf.enable_hwc_vds=1$' "$BP"
awk '$0=="debug.sf.enable_hwc_vds=1"{print "debug.sf.enable_hwc_vds=0"; next} {print}' "$BP" > "$R/build.prop.8i"
cat "$R/build.prop.8i" > "$BP"
rm -f "$R/build.prop.8i"
need_grep '^debug.sf.enable_hwc_vds=0$' "$BP"
forbid_grep '^debug.sf.enable_hwc_vds=1$' "$BP"
need_grep '^vendor.display.vds_allow_hwc=1$' "$T/product/etc/build.prop"
echo "edited  system build.prop: debug.sf.enable_hwc_vds=0 (stock; 7t undone)"
set_layer "$STEP"
