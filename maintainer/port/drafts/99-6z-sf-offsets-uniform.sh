#!/bin/sh
# Step 6z (BUGS 115, 2026-11-15): one SurfaceFlinger phase offset for late, early and earlyGl: -6.5 ms (app offsets stay
# the vendor late +1 ms). Replaces the trade-off of the two earlier settings:
# * 2l (pt97): early/earlyGl -6.5 ms, late -4 ms (vendor). SF switched timing on every animation; at 144 Hz that moved
#   frames by one vsync = judder while the media pill animates (144 Hz + music: 8-9 % janky).
# * 6y (pt99): -4 ms everywhere (HyperOS vendor). No judder, but under heavy load SF ran one frame behind at 120 Hz
#   (SF Stuffing 975/657 fresh boot vs 36/26 on pt97) and dropped more frames.
# * 6z (C3): -6.5 ms everywhere = no switch and the slack of 2l. A/B 2026-11-15, same boot after SF restarts, traced_heavy
#   x2 + 144 Hz Spotify-pill Opera scroll: dropped 19/21 vs 94/58 (-4 ms), SF Stuffing 22/13 vs 483/443, GPU deadline
#   6/8 vs 66/24, launcher FrameTimeline janky 38/38 vs 52/51 %, 144 Hz pill 0.2 vs 0.3 %. Cost: SF starts 2.5 ms
#   earlier (latency); HWC commits wait longer for vblank (sleep, no CPU).
set -eu
. "$PORT/lib.sh"
STEP=6z

BP=$T/product/etc/build.prop
need_grep 'pipa port 6y' "$BP"
forbid_grep 'high_fps_late_sf_phase_offset_ns' "$BP"
printf '%s\n' '' '# pipa port 6z: one SF phase offset for late/early/earlyGl (no early/late switch; BUGS 115)' \
    'debug.sf.high_fps_late_sf_phase_offset_ns=-6500000' 'debug.sf.high_fps_early_phase_offset_ns=-6500000' \
    'debug.sf.high_fps_early_gl_phase_offset_ns=-6500000' > "$R/6z.prop"
{ cat "$BP"; cat "$R/6z.prop"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"; rm -f "$R/build.prop.new" "$R/6z.prop"   # same inode: label kept
need_grep '^debug.sf.high_fps_late_sf_phase_offset_ns=-6500000$' "$BP"
tail -4 "$BP"

set_layer "$STEP"
