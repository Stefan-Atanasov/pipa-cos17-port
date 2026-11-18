#!/bin/sh
# Step 7k (BUGS 125, user 2026-11-17): landscape home page-indicator pill touched labels and dock on the 16:10 panel.
# OplusLauncher places the grid at leftover-height x workspaceTopPercentage (stock tablet overlay: land 0.25); on pipa the
# leftover is slightly negative, so the last row sits on the pill. Static RRO com.port.pipa.overlay.launchergrid (not .launcher = old porter overlay removed in 6p; priority 903 >
# OPPO LauncherResourceOverlay 22) sets values-land workspaceTopPercentage=1.0: grid lifts into the space under the clock,
# pill gets a gap above and below; portrait, margins and dock stay stock. Live-tested 2026-11-17 (fabricated overlay).
# 2026-11-18 (overlay v2): 1.0 put the top row under the media island. 6 rows were 54 px too tall for the 16:10 panel:
# values-land oplusLayoutWorkspacePaddingHorBigScreenDp 102 -> 130 dp (cell = width, 240 -> 227 px) + top 0. Live-tested.
# Build the APK first: sh maintainer/overlays/launcher/build.sh
#NEEDS: "$HERE/overlays/launcher/out/PipaLauncherGridOverlay.apk"
set -eu
. "$PORT/lib.sh"
STEP=7k
O=$T/product/overlay
[ -d "$O" ] || die "no $O"
SIB=$(ls "$O"/*.apk | head -1)
D=$O/PipaLauncherGridOverlay
[ -e "$D" ] && die "$D exists already"
mkdir "$D"
chmod 755 "$D"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$O")" "$D"
F=$D/PipaLauncherGridOverlay.apk
cp -p "$SIB" "$F"                       # owner, mode (cp -p keeps no SELinux label: set below)
cat "$HERE/overlays/launcher/out/PipaLauncherGridOverlay.apk" > "$F"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
echo "added   product/overlay/PipaLauncherGridOverlay/PipaLauncherGridOverlay.apk"
md5sum "$F"
set_layer "$STEP"
