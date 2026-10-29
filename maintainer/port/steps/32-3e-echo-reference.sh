#!/bin/sh
# Phase 3e: call sharing without echo for the far end (BUGS-TODO 27), on top of 3d (vendor + system_ext).
#
# com.oplus.vdc records the pad mic with source VOICE_COMMUNICATION: the HAL uses audio-record-voip = MultiMedia10,
# and the DSP echo canceller reads its reference from AUDIO_REF_EC_UL10 MUX. A shared call is a telephony call
# (MODE_IN_CALL), and the CAF HAL adds "-voip" to the echo-reference path only in MODE_IN_COMMUNICATION, so it set
# only AUDIO_REF_EC_UL1 MUX: no reference, the far end heard itself.
# * vendor/etc/mixer_paths.xml + mixer_paths_overlay_static.xml: module/tools/patch_ec_ref.py copies the UL1 value
#   of each echo-reference path to UL10 (and adds "echo-reference handset" to the base file).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3e.
#
# Old layer script: build_beta5_3e.sh
#NEEDS: "$TOOLS/patch_ec_ref.py"
set -eu
. "$PORT/lib.sh"
STEP=3e

SE=$T/system_ext
V=$T/vendor

echo "== 27: echo reference for the VoIP capture in MODE_IN_CALL"
python3 -I "$HERE/../module/tools/patch_ec_ref.py" base "$V/etc/mixer_paths.xml" "$R/mixer_paths.xml"
python3 -I "$HERE/../module/tools/patch_ec_ref.py" overlay "$V/etc/mixer_paths_overlay_static.xml" "$R/mixer_paths_overlay_static.xml"
for f in mixer_paths.xml mixer_paths_overlay_static.xml; do
    cat "$R/$f" > "$V/etc/$f"   # same inode: label kept
    echo "edited  vendor/etc/$f"
done
need_grep 'AUDIO_REF_EC_UL10 MUX' "$V/etc/mixer_paths.xml"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

