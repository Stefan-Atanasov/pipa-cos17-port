#!/bin/sh
# Phase 4f: framework values for Circle to Search (BUGS-TODO 49; product only).
#
# SystemServer starts ContextualSearchManagerService ("contextual_search") only when
# config_defaultContextualSearchPackageName is set; ColorOS CN leaves it empty, so ColorOS's own Circle to Search
# path (ContextualManagerServiceExtImpl) had no service. The static overlay PipaContextualSearchOverlay sets the
# Pixel values (googlequicksearchbox, omni.entry_point, omni.enable_cs_helper, omni.enable_vis).
# Live test 2026-11-02 (bind mount of /product/overlay + zygote restart): service up,
# isContextualSearchAvailable = true, startContextualSearch opens Google's Circle to Search.
# Build the APK first: sh maintainer/cts/overlay/build.sh
#NEEDS: "$HERE/cts/overlay/out/PipaContextualSearchOverlay.apk"
set -eu
. "$PORT/lib.sh"

O=$T/product/overlay
[ -d "$O" ] || die "no $O"
SIB=$(ls "$O"/*.apk | head -1)
D=$O/PipaContextualSearchOverlay
[ -e "$D" ] && die "$D exists already"
mkdir "$D"
chmod 755 "$D"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$O")" "$D"
F=$D/PipaContextualSearchOverlay.apk
cp -p "$SIB" "$F"                       # owner, mode (cp -p keeps no SELinux label: set below)
cat "$HERE/cts/overlay/out/PipaContextualSearchOverlay.apk" > "$F"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
echo "added   product/overlay/PipaContextualSearchOverlay/PipaContextualSearchOverlay.apk"
