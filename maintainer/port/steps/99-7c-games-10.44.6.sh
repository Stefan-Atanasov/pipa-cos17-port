#!/bin/sh
# Step 7c (user 2026-11-15 "add the game assistant latest version preinstalled"): Game Space (com.oplus.games,
# Game Assistant) 10.44.6 instead of the donor's 10.40.22 (my_stock/priv-app/OplusGames).
# * Source: the update OPPO's own App Market (com.heytap.market) installed on the maintainer tablet 2026-11-05,
#   pulled from /data/app. Same OPPO signing certificate as the donor APK (apksigner, SHA-256 c9305ee3...).
#   Ran on the port 10 days (PUBG Game Assistant, Ultra touch tests BUGS 117).
# * extractNativeLibs=false in both versions (30 arm64 libs stored), so the APK is a drop-in.
# * New permission: MODIFY_AUDIO_ROUTING, already allowlisted for com.oplus.games in
#   my_stock/etc/permissions/privapp-permissions-oplus-product.xml.
# * The donor oat/ (vdex for 10.40.22) is removed; ART compiles the new APK.
# * A newer donor with a different OplusGames.apk stops the step: check its version, then update or drop this step.
# Blob (not in git, 159 MB): $P/blobs/OplusGames-10.44.6.apk  md5 9e733a0c203b104113de17a9f2ca5a37
# (backup copy: /mnt/reference/pipa/port-work/blobs/)
#NEEDS: "$P/blobs/OplusGames-10.44.6.apk"
set -eu
. "$PORT/lib.sh"
STEP=7c

NEW=$P/blobs/OplusGames-10.44.6.apk
[ "$(md5sum < "$NEW" | cut -d' ' -f1)" = 9e733a0c203b104113de17a9f2ca5a37 ] || die "blob md5 mismatch: $NEW"
D=$T/system/my_stock/priv-app/OplusGames
A=$D/OplusGames.apk
[ -f "$A" ] || die "no $A"
old=$(md5sum < "$A" | cut -d' ' -f1)
[ "$old" = 75d21707e6b25229049e0e7d2924396d ] || die "donor OplusGames.apk changed (md5 $old, expected 10.40.22): check its version first"
cat "$NEW" > "$A"   # in place: owner, mode and SELinux label stay
rm -rf "$D/oat"
[ "$(md5sum < "$A" | cut -d' ' -f1)" = 9e733a0c203b104113de17a9f2ca5a37 ] || die "copy failed"
echo "replaced my_stock/priv-app/OplusGames/OplusGames.apk: 10.40.22 -> 10.44.6 (oat removed)"

set_layer "$STEP"
