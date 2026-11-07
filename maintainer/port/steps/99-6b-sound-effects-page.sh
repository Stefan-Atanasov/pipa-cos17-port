#!/bin/sh
# Phase 6b (beta8): Settings > Sound > Sound effect settings shows only what pipa has, in English.
#
# beta4's PipaMiSoundOverlay replaced ColorOS's sound effects page with fixed Chinese text: a MiSound entry on top of
# ColorOS's own controls. Those controls need OPPO's effect libraries (AudioX "OReality" modes Smart / Immersive /
# Fidelity / Custom, oplus spatializer, MSS sound field, volume boost; on OPPO devices libOplusAudioxAidl.so and
# friends in odm), which pipa's Xiaomi vendor does not have (its effects: Dolby DAX3 + misoundfx, as on stock
# HyperOS). They saved a setting and changed nothing (user report 2026-11-07, screenshot of the mode grid).
# The new overlay (maintainer/overlays/misound, signed with the helper key) keeps the MiSound entry (Dolby Atmos,
# sound mode, equalizer) in English and leaves out the controls SoundEffectsFragment always shows (current device,
# effect selector, OReality mode grid; the fragment null-checks them). The others stay in the XML because their
# controllers need them (MssSpatialRenderController crashes Settings without key_mss_spatial_render) and the fragment
# hides them itself when the feature is missing. A hidden parent category does not work: ColorOS's preference list
# still shows the children (pt77). Tested live on pt77 (bind mount + zygote restart): page shows only the MiSound
# entry, entry opens MiSound, reopen OK, 0 crashes.
#NEEDS: "$HERE/overlays/misound/out/PipaMiSoundOverlay.apk"
set -eu
. "$PORT/lib.sh"
STEP=6b

APK=$HERE/overlays/misound/out/PipaMiSoundOverlay.apk
[ -f "$APK" ] || die "build the overlay first: sh maintainer/overlays/misound/build.sh"
F=$T/system/my_product/overlay/PipaMiSoundOverlay.apk
[ "$(md5sum < "$F" | cut -d' ' -f1)" = 49eec90ac12f217270b7fb9face771dc ] || die "$F: not beta4's overlay"
LABEL=$(getfattr -n security.selinux --only-values "$F")
cat "$APK" > "$F"    # same inode, owner, mode and label (vendor_overlay_file)
[ "$(getfattr -n security.selinux --only-values "$F")" = "$LABEL" ] || die "label changed: $F"
echo "edited  system/my_product/overlay/PipaMiSoundOverlay.apk"
md5sum "$F"
set_layer "$STEP"
