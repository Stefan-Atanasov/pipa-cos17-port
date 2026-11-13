#!/bin/sh
# Step 6p (BUGS-TODO 94, user 2026-11-10): home screen wastes space (wide side margins, gap above the dock).
# Cause (2026-11-13, port-work/codex/bugs94-margins/REPORT.md): the beta4 porter overlay PipaLauncherOverlay.apk
# (com.port.pipa.overlay.launcher, priority 9999, carried from port-overlay) sets
# oplusLayoutWorkspacePaddingHorBigScreenDp=150 (+ hotseat gesture margin 20). OPPO's own tablet overlay
# LauncherResourceOverlay (com.oplus.android.launcher.overlay.tablet) sets 80 dp portrait / 102 dp landscape.
# Fix = stock: remove the porter overlay. Live test 2026-11-13 (fabricated overlay 80/102 on pt88): portrait 6 columns
# fill the width, landscape grid wider, smaller dock gap.
set -eu
. "$PORT/lib.sh"
STEP=6p
echo "== 6p launcher margins: remove the porter launcher overlay"
O=$T/system/my_product/overlay/PipaLauncherOverlay.apk
[ -f "$O" ] || die "no $O (already removed?)"
rm -f "$O"
[ -f "$T/system/my_product/overlay/LauncherResourceOverlay/LauncherResourceOverlay.apk" ] || die "OPPO LauncherResourceOverlay missing"
echo "removed my_product/overlay/PipaLauncherOverlay.apk"
set_layer "$STEP"
