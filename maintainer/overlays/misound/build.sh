#!/bin/sh
# Build PipaMiSoundOverlay (static RRO on com.android.settings: Sound effects page -> MiSound). Output: out/PipaMiSoundOverlay.apk
# Signed with the helper key (helper/keys, private, never shared).
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/37.0.0
JAR=$SDK/platforms/android-37.0/android.jar
KEYS=../../../helper/keys
KSPASS=${KSPASS:-$(cat "$KEYS/keystore.pass")}
rm -rf out && mkdir -p out
"$BT/aapt2" compile --dir res -o out/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml --min-sdk-version 35 --target-sdk-version 37 -o out/unsigned.apk out/res.zip
"$BT/zipalign" -f -p 4 out/unsigned.apk out/aligned.apk
"$BT/apksigner" sign --ks "$KEYS/pipa-helper.jks" --ks-pass "pass:$KSPASS" --out out/PipaMiSoundOverlay.apk out/aligned.apk
"$BT/apksigner" verify out/PipaMiSoundOverlay.apk
md5sum out/PipaMiSoundOverlay.apk
