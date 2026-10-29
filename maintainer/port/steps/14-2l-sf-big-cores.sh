#!/bin/sh
# Phase 2l: smoothness (2026-10-24 stutter root cause, kernel/KERNEL-RESEARCH.md "2026-10-24 morning"), on top of 2k.
#
# * pipa_port: SF_BIG_CORES sets the UI First kernel scene SA_GPU_COMPOSITION at boot, so SurfaceFlinger and
#   RenderEngine (realtime) stay off the little cores (OPPO's vendor daemon sets it on OPPO phones; pipa's vendor never
#   does). FrameTimeline: SF dropped frames -58 %, GPU-deadline misses -52 %, power +2 % under heavy use.
# * product build.prop (loads after vendor, whose HyperOS values would win otherwise): SF early/earlyGl phase offset
#   -6.5 ms (GPU-composed animation frames missed the vblank with -4 ms), early app offsets -1.5 ms (apps keep their
#   draw time), predict_hwc_composition_strategy=1 (vendor forces 0; 2j's system_ext value never applied).
#
# Old layer script: build_beta5_2l.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
PR=$T/product

# in place (cat >): owner, mode and SELinux label stay
echo "== pipa_port"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
need_grep SF_BIG_CORES "$SE/pipa_port/service.sh"

echo "== product build.prop: SurfaceFlinger timing"
BP=$PR/etc/build.prop
grep -q 'high_fps_early_gl_phase_offset_ns' "$BP" && { echo "already patched"; exit 1; }
printf '%s\n' '' '# pipa port 2l: SF timing for GPU-composed animation frames (vendor sets -4 ms everywhere; 2026-10-24 A/B)' \
    'debug.sf.high_fps_early_phase_offset_ns=-6500000' 'debug.sf.high_fps_early_gl_phase_offset_ns=-6500000' \
    'debug.sf.high_fps_early_app_phase_offset_ns=-1500000' 'debug.sf.high_fps_early_gl_app_phase_offset_ns=-1500000' \
    'debug.sf.predict_hwc_composition_strategy=1' >> "$BP"
tail -6 "$BP"

