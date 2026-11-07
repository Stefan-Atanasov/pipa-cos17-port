#!/bin/sh
# 6c: no DSP voice wake-up ("Hey Breeno"). Tester log 2026-11-07: with voice wake-up on,
# com.oplus.ovoicemanager.wakeup loads its phrase model (OVMS_settings.xml: Qualcomm SVA vendor uuid
# 68ac2d41-e861-11e4-95ed-0002a5d5c51c, model 7d5b82e9-...). pipa's Xiaomi sound-trigger platform info has no
# such vendor: sound_trigger_hw logs "stdev_load_sound_model: no matching vendor uuid found" and the audio HAL
# process dies. Android restarts it, the wake-up service loads the model again: 30 audio HAL crashes in 6 minutes,
# sound drops during playback, Breeno microphone fails (BUGS 79 "Breeno mic").
# Stock behaviour for a device without DSP wake-up: the feature flags are absent, so Breeno does not offer DSP
# voice wake-up. Comment them out like the AOD flags in 2a.
set -eu
. "$PORT/lib.sh"

echo "== 6c DSP voice wake-up flags off"
F=system/my_product/etc/extension/com.oplus.oplus-feature.xml
for f in audio.voice_wakeup_xbxb_support audio.voice_wakeup_support speechassist.oneshot.support \
         audio.voice_wakeup_concurrent_capture; do
    replace_once $F "\t<oplus-feature name=\"oplus.software.$f\"/>\n" \
        "\t<!-- pipa port 6c: no DSP wake-up <oplus-feature name=\"oplus.software.$f\"/> -->\n"
done
grep -c 'pipa port 6c' "$T/$F"
