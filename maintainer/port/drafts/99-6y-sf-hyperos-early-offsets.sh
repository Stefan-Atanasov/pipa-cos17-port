#!/bin/sh
# Step 6y (BUGS 115, 2026-11-15): SurfaceFlinger early phase offsets back to the HyperOS vendor values for this panel.
# * 2l (2026-10-24) put early/earlyGl SF -6.5 ms and early app -1.5 ms in product build.prop (it loads after vendor).
#   Reason then: GPU-composed frames missed the vblank with -4 ms while SF and RenderEngine ran on the little cores.
#   SF_BIG_CORES (2l) and walt-r4 (RenderEngine) fixed that cause since.
# * With -6.5 ms, SF switches between early and late timing whenever an animation runs. At 144 Hz (6.9 ms frames) the
#   switch moves frames by one vsync: present latency mixes 1 and 2 vsyncs = judder. Tester report: browser scroll lags
#   while music/YouTube plays in the background (the media pill animates at 30 fps all the time).
# * A/B 2026-11-15, pt97 + walt-hi1, same boot, runtime props + SF restart, Opera scroll by kgest:
#   144 Hz + Spotify pill: SF-scheduling jank 8-9 % (-6.5 ms) -> 0.5 % (-4 ms); 120 Hz + pill 0.9 % -> 0.2 %.
#   Auto (traced_heavy): SystemUI janky 17.1/12.9 % -> 13.1/8.8 %, long DRM commits 360 -> 13/8, SF Stuffing <=10 both.
# Removes only the four offset lines of 2l; debug.sf.predict_hwc_composition_strategy=1 (2l) stays.
set -eu
. "$PORT/lib.sh"
STEP=6y

BP=$T/product/etc/build.prop
need_grep '^debug.sf.high_fps_early_phase_offset_ns=-6500000$' "$BP"
replace_once "$BP" "debug.sf.high_fps_early_phase_offset_ns=-6500000\ndebug.sf.high_fps_early_gl_phase_offset_ns=-6500000\ndebug.sf.high_fps_early_app_phase_offset_ns=-1500000\ndebug.sf.high_fps_early_gl_app_phase_offset_ns=-1500000\n" \
    "# pipa port 6y: early phase offsets of 2l removed (HyperOS vendor values apply, BUGS 115)\n"
forbid_grep 'high_fps_early' "$BP"
need_grep '^debug.sf.predict_hwc_composition_strategy=1$' "$BP"
tail -4 "$BP"

set_layer "$STEP"
