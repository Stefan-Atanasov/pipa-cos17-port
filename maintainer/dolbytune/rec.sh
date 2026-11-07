#!/bin/bash
# rec.sh <out.wav>: record the Fifine while the tablet plays /data/local/tmp/${SWEEP:-sweep10}.wav
S=$(dirname "$0")
pw-record --target alsa_input.usb-3142_Fifine_Microphone-00.mono-fallback --rate 48000 --channels 1 --format s24 "$1" &
P=$!; sleep 0.7
adb -s 83836a90 shell "CLASSPATH=/data/local/tmp/play.dex app_process /system/bin Play /data/local/tmp/${SWEEP:-sweep10}.wav" >/dev/null 2>&1
sleep 0.5; kill -INT $P; wait $P 2>/dev/null
