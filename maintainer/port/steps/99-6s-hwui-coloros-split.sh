#!/bin/sh
# Step 6s (BUGS-TODO 109, user 2026-11-14 "smooth as stock OPPO"): ColorOS's own HWUI renderer split, as on stock OPPO
# tablets: ro.oplus.display.enable_skiavk=true makes libhwui use Vulkan only for its built-in list (launcher, SystemUI,
# camera, wallpapers, colorfulengine) and OpenGL for every other app. The beta4 porter forced Vulkan for all apps
# (vendor/build.prop debug.hwui.renderer=skiavk + ro.hwui.use_vulkan=true, his "global Vulkan" test of 2026-10-14);
# his own notes say OpenGL is the always-correct path for app video (Vulkan + Adreno gralloc: swapped chroma / green
# grid lines on some HW-decoded video). Stock HyperOS pipa also runs apps on OpenGL.
# Live A/B 2026-11-14 on pt92 (temporary resetprop at post-fs-data, same tests): Documents sheet 36.5 % -> 31-34 %
# janky, median 30 -> 22 ms; YouTube 4.5 -> 1.0 %; Play 1.1 -> 0 %; Spotify 0 -> 0.3 %; launcher 0.7 -> 0.65 %.
# SystemUI/launcher stay on Vulkan (gfxinfo Pipeline=Skia (Vulkan)); apps show Skia (OpenGL).
set -eu
. "$PORT/lib.sh"
STEP=6s
V=$T/vendor/build.prop
need_grep '^debug.hwui.renderer=skiavk$' "$V"
need_grep '^ro.hwui.use_vulkan=true$' "$V"
need_grep '^# ro.oplus.display.enable_skiavk=true$' "$V"

echo "== 6s vendor build.prop: ColorOS HWUI split (Vulkan for system UI, OpenGL for apps)"
replace_once "$V" 'debug.hwui.renderer=skiavk
ro.hwui.use_vulkan=true' '# 6s: removed (stock ColorOS split below): debug.hwui.renderer=skiavk
# 6s: removed: ro.hwui.use_vulkan=true'
replace_once "$V" '# ro.oplus.display.enable_skiavk=true' 'ro.oplus.display.enable_skiavk=true'
forbid_grep '^debug.hwui.renderer=' "$V"
forbid_grep '^ro.hwui.use_vulkan=' "$V"
need_grep '^ro.oplus.display.enable_skiavk=true$' "$V"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
