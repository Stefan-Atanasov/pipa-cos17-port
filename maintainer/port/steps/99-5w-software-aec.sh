#!/bin/sh
# Phase 5w (beta7.2, BUGS-TODO 27): software echo canceller for voice chat (games, VoIP apps, call sharing).
#
# The pipa DSP echo canceller cancels nothing in the VoIP path (HISTORY 2026-10-29, 2026-11-06): apps that rely on
# the system AEC (PUBG/BGMI voice chat, call sharing) send the speaker sound back to the far end.
# maintainer/aecshim (own C code, build.sh) is loaded as vendor/lib/hw/audio.primary.kona.so. It loads the real HAL
# (audio.primary.kona.so, unchanged; the wrapper is audio.primary.pipaaec.so, chosen by ro.hardware.audio.primary),
# copies every PCM output as the far-end reference and
# runs the AOSP WebRTC AEC3 (vendor/lib/soundfx/libaudiopreprocessing.so, mobile mode off) on every
# VOICE_COMMUNICATION input (16-bit mono, 8/16/48 kHz), then AGC2 +24 dB (the voice-chat mic path is quiet).
# DSP noise suppression stays.
# Live test 2026-11-06 (echotest, vol 5): echo during playback -8.9 dBFS -> -26..-39 dBFS (most 0.5 s windows at
# the room floor); a near-end source without playback keeps its level (wrapper off/on: -31/-30 dBFS).
# Switches (read when an input opens): persist.vendor.audio.pipa_aec 0 = off, persist.vendor.audio.pipa_aec_gain
# 0-30 dB (default 24). Call sharing test with a real call: echo gone after the first seconds.
#NEEDS: "$ROM/pipa_aec/audio.primary.kona.so"
set -eu
. "$PORT/lib.sh"
STEP=5w

H=$T/vendor/lib/hw
VP=$T/vendor/build.prop
[ -f "$H/audio.primary.kona.so" ] || die "audio HAL missing: $H/audio.primary.kona.so"
[ -f "$VP" ] || die "vendor build.prop missing"
[ -e "$H/audio.primary.pipaaec.so" ] && die "audio.primary.pipaaec.so exists: step 5w already applied?"
forbid_grep '^ro.hardware.audio.primary=' "$VP"
[ -f "$T/vendor/lib/soundfx/libaudiopreprocessing.so" ] || die "vendor/lib/soundfx/libaudiopreprocessing.so missing"
need_grep 'pipa AEC wrapper' "$ROM/pipa_aec/audio.primary.kona.so"
need_grep '/vendor/lib/hw/audio.primary.kona.so' "$ROM/pipa_aec/audio.primary.kona.so"

# The real HAL keeps its name: the sound trigger HAL loads audio.primary.<ro.board.platform>.so by name and calls
# its audio_extn/audio_hw functions (pt65 renamed it: boot hang, watchdog reboot loop, 2026-11-06).
# libhardware checks ro.hardware.audio.primary first, so only the audio service loads the wrapper.
install -o 0 -g 0 -m 644 "$ROM/pipa_aec/audio.primary.kona.so" "$H/audio.primary.pipaaec.so"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$H/audio.primary.kona.so")" \
    "$H/audio.primary.pipaaec.so"
printf '\n# pipa port 5w: audio HAL wrapper with software AEC (real HAL: audio.primary.kona.so)\nro.hardware.audio.primary=pipaaec\n' >> "$VP"
need_grep '^ro.hardware.audio.primary=pipaaec' "$VP"
md5sum "$H/audio.primary.pipaaec.so" "$H/audio.primary.kona.so"
