#!/bin/sh
# Phase 8k (2026-11-20, BUGS 139/159): MediaRecorder with AAC audio failed in every app ("prepare failed"; GCam 8.8
# video: StagefrightRecorder "Failed to create audio encoder", ACodec "Unexpected nullptr for codec information").
# Qualcomm's ExtendedSFRecorder (system_ext libavenhancements) creates its own OMX audio encoder unless
# vendor.audio.c2.preferred is set ("CCodec preferred, skip creation of custom OMX audio encoders"). Stock HyperOS
# has the OMX encoder (vendor libOmxAacEnc.so, vendor.audio.hw.aac.encoder=true); the beta4 vendor has no OMX audio
# libraries. So the recorder uses the Codec2 AAC encoder (c2.android.aac.encoder). Live test pt137: GCam 8.8 video
# 1080p HEVC + AAC 48 kHz stereo saved.
# * The line is in product/etc/build.prop (pt139+). pt138 had it in vendor/build.prop and it worked too: the "empty"
#   check was `getprop` as the adb shell user, which may not read vendor_audio_prop (avc denied); read it as root.
set -eu
. "$PORT/lib.sh"
STEP=8k
VB=$T/product/etc/build.prop
[ -f "$VB" ] || die "no $VB"
for f in $(find "$T" -maxdepth 4 -name build.prop -type f); do forbid_grep '^vendor.audio.c2.preferred=' "$f"; done
{ cat "$VB"; printf '%s\n' "# pipa port 8k (BUGS 159): no OMX audio encoders in this vendor; recorder uses Codec2" "vendor.audio.c2.preferred=true"; } > "$R/product.build.prop.8k"
cat "$R/product.build.prop.8k" > "$VB"; rm -f "$R/product.build.prop.8k"
need_grep '^vendor.audio.c2.preferred=true$' "$VB"
set_layer "$STEP"
