#!/bin/sh
# Step 7i (BUGS 101, 2026-11-16): fixed network location provider = the OPPO NLP (com.oplus.location), like stock.
# GMS NLP and OPPO NLP both declare serviceVersion 2 and are system apps. framework-res has
# config_enableNetworkLocationOverlay=true and no package, so CurrentUserServiceSupplier binds the first
# queryIntentServices result on a tie (strict >): the choice can flip after an update (tester: location lost after a
# dirty flash 7.1 -> 8). Stock ColorOS CN has no tie (GMS off at first boot; our 4d turns GMS on). Overlay
# maintainer/overlays/location (static RRO, /product -> product policy; GmsConfigOverlayCommonCN in /my_product is
# not applied at all, STATE_NO_IDMAP) sets the switch false and names com.oplus.location. The OPPO NLP gives Wi-Fi
# fixes in ~13 s on our tablet (Bulgaria); apps that use Google Play location keep GMS fused location.
# Report: port-work/codex/location-pin-20261116/REPORT.md. Build the APK first: sh maintainer/overlays/location/build.sh
#NEEDS: "$HERE/overlays/location/out/PipaLocationOverlay.apk"
set -eu
. "$PORT/lib.sh"
STEP=7i
O=$T/product/overlay
[ -d "$O" ] || die "no $O"
SIB=$(ls "$O"/*.apk | head -1)
D=$O/PipaLocationOverlay
[ -e "$D" ] && die "$D exists already"
mkdir "$D"
chmod 755 "$D"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$O")" "$D"
F=$D/PipaLocationOverlay.apk
cp -p "$SIB" "$F"                       # owner, mode (cp -p keeps no SELinux label: set below)
cat "$HERE/overlays/location/out/PipaLocationOverlay.apk" > "$F"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
echo "added   product/overlay/PipaLocationOverlay/PipaLocationOverlay.apk"
md5sum "$F"
set_layer "$STEP"
