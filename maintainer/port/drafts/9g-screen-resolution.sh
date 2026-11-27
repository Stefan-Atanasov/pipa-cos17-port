#!/bin/sh
# Step 9g (2026-11-25, user wish): Settings > Display > Screen resolution (High 2880x1800 / Low 2304x1440), the stock
# ColorOS "fake resolution" switch for panels with one native mode (pipa: only 1800x2880 modes at 60/90/120/144 Hz).
# oplus-services OplusResolutionSwitchImpl: with oplus.software.display.wm_size_resolution_switch_support and one panel
# resolution it switches by forced display size + density (secure oplus_customize_screen_resolution_adjust 2 = low,
# 3 = high), with its own switch animation and the app stop/restart list of sys_resolution_switch_config.xml.
# Settings (com.oplus.settings.feature.display.ScreenResolutionController) shows the entry with
# oplus.software.display.resolution_switch_support.
# Sizes are portrait "W,H" (WindowManager base size); Low = x0.8, density x0.8 (same dp layout, exact integers):
#   high 1800,2880 @ 370 (Display size 340/370/410), low 1440,2304 @ 296 (272/296/328), 247 ppi.
# Measured 2026-11-25 (pt163, wm size, Rich, traced_heavy): native 2.4-3.1 % SF frames dropped, x0.8 1.1 %, x0.75 0.9 %
# (GPU deadline missed 94-118 -> 35 both): x0.8 = same smoothness, sharper.
# SurfaceFlinger still composes at 1800x2880 (framebufferSpace) with a forced size. Tested 2026-11-25 on pt164:
# ro.surface_flinger.max_graphics_* 1440x2304 (init trigger) -> SF framebuffer 1440x2304, but the QTI HWC does not scale
# the client target (picture zoomed, offset to the bottom left): removed. QTI's own path is vendor.display.fb_width/
# fb_height: applied at HWC start, then reset to 1800x2880 by the first display mode (refresh rate) change (BUGS 196).
# sys_resolution_switch_config.xml (donor: OPD2515 panel, screenwidth 2400, app scale density 420 = x0.75 of 560):
# screenwidth -> 1800 (pipa physical width: a cloud copy for another panel is ignored), the default and per-game app
# scale densities -> pipa (x0.75 = 278, x0.8 = 296); default app scale = x0.8.
set -eu
. "$PORT/lib.sh"
STEP=9g
MP=$T/system/my_product
F=$MP/etc/permissions/oplus.product.display_features.xml
[ -f "$F" ] || die "no $F"
forbid_grep 'resolution_switch_support' "$F"
replace_once "$F" '</oplus-config>' \
'    <!-- pipa port 9g: Screen resolution High/Low through wm size (one native panel mode) -->
    <oplus-feature name="oplus.software.display.resolution_switch_support"/>
    <oplus-feature name="oplus.software.display.wm_size_resolution_switch_support"/>
</oplus-config>'
need_grep 'oplus.software.display.wm_size_resolution_switch_support' "$F"

BP=$T/product/etc/build.prop
need_grep '^ro.density.screenzoom=340,370,410$' "$BP"
forbid_grep '^ro.oplus.resolution' "$BP"
{ cat "$BP"; cat <<'EOF'
# pipa port 9g: Screen resolution switch (OplusResolutionSwitchImpl, wm size): high = native, low = x0.8
ro.oplus.resolution.high=1800,2880
ro.oplus.resolution.low=1440,2304
ro.oplus.density.qhd_default=370
ro.oplus.density.fhd_default=296
ro.density.screenzoom.qdh=340,370,410
ro.density.screenzoom.fdh=272,296,328
EOF
} > "$R/build.prop.9g"
cat "$R/build.prop.9g" > "$BP"; rm -f "$R/build.prop.9g"   # same inode: label, owner and mode kept
need_grep '^ro.oplus.resolution.low=1440,2304$' "$BP"

C=$MP/etc/sys_resolution_switch_config.xml
[ -f "$C" ] || die "no $C"
need_grep 'screenwidth="2400"' "$C"
need_grep '<scaleinfo value="1.17037,0.85443,320" />' "$C"
sed -e 's/screenwidth="2400"/screenwidth="1800"/' \
    -e 's|<scaleinfo value="1.17037,0.85443,320" />|<scaleinfo value="1.25,0.8,296" />|' \
    -e 's/scaleinfo="1.33,0.75,420"/scaleinfo="1.33333,0.75,278"/g' \
    -e 's/scaleinfo="1.25,0.8,420"/scaleinfo="1.25,0.8,296"/g' "$C" > "$R/res.9g"
cat "$R/res.9g" > "$C"; rm -f "$R/res.9g"
need_grep 'screenwidth="1800"' "$C"
forbid_grep '0.75,420"\|0.8,420"' "$C"   # the com.example.* sample lines keep theirs
echo "Screen resolution: features, ro.oplus.resolution.*, density lists, switch config for 1800x2880"
set_layer "$STEP"
