#!/bin/sh
# Build the Circle to Search framework overlay (step 4f): aapt2 + zipalign + apksigner.
# Key: keys/overlay.jks (made on the first run; private, git-ignored). A static RRO on /product needs no platform key.
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$(ls -d "$SDK"/build-tools/*/ | tail -1); JAR=$(ls -d "$SDK"/platforms/android-3*/ | tail -1)android.jar
rm -rf out && mkdir -p out keys
"$BT/aapt2" compile --dir res -o out/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o out/unsigned.apk out/res.zip
"$BT/zipalign" -f 4 out/unsigned.apk out/aligned.apk
[ -f keys/overlay.jks ] || keytool -genkeypair -keystore keys/overlay.jks -storepass pipaoverlay -keypass pipaoverlay \
    -alias overlay -keyalg RSA -keysize 2048 -validity 20000 -dname "CN=pipa port overlay" >/dev/null 2>&1
"$BT/apksigner" sign --ks keys/overlay.jks --ks-pass pass:pipaoverlay --out out/PipaContextualSearchOverlay.apk out/aligned.apk
md5sum out/PipaContextualSearchOverlay.apk
