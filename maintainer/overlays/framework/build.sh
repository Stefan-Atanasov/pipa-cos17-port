#!/bin/sh
# Build PipaFrameworkOverlay (static RRO on "android", step 6i): aapt2 + zipalign + apksigner.
# Key: the overlay key of the Circle to Search overlay (maintainer/cts/overlay/keys/overlay.jks; private,
# git-ignored; run maintainer/cts/overlay/build.sh one time to make it). A static RRO on /product needs no platform key.
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$(ls -d "$SDK"/build-tools/*/ | tail -1); JAR=$(ls -d "$SDK"/platforms/android-3*/ | tail -1)android.jar
KS=../../cts/overlay/keys/overlay.jks
[ -f "$KS" ] || { echo "no $KS: run maintainer/cts/overlay/build.sh first" >&2; exit 1; }
rm -rf out && mkdir -p out
"$BT/aapt2" compile --dir res -o out/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o out/unsigned.apk out/res.zip
"$BT/zipalign" -f 4 out/unsigned.apk out/aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:pipaoverlay --out out/PipaFrameworkOverlay.apk out/aligned.apk
"$BT/apksigner" verify out/PipaFrameworkOverlay.apk
md5sum out/PipaFrameworkOverlay.apk
