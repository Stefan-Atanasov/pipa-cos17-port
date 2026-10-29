#!/bin/sh
# Build the echo test app (BUGS-TODO 27) without Gradle, like helper/build.sh. Output: out/Probe.apk.
# Signed with a throwaway test key (out/test.jks, password "android"): this app is never part of the ROM.
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/37.0.0
JAR=$SDK/platforms/android-37.0/android.jar
rm -rf out/classes out/dex && mkdir -p out/classes out/dex
[ -f out/test.jks ] || keytool -genkeypair -keystore out/test.jks -storepass android -keypass android -alias test \
    -keyalg RSA -keysize 2048 -validity 36500 -dname "CN=pipa probe" >/dev/null
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o out/unsigned.apk
javac --release 17 -Xlint:-options -cp "$JAR" -d out/classes $(find src -name '*.java')
"$BT/d8" --release --min-api 35 --lib "$JAR" --output out/dex $(find out/classes -name '*.class')
python3 - <<'EOF'
import zipfile
with zipfile.ZipFile("out/unsigned.apk", "a") as z:
    z.write("out/dex/classes.dex", "classes.dex")
EOF
"$BT/zipalign" -f -p 4 out/unsigned.apk out/aligned.apk
"$BT/apksigner" sign --ks out/test.jks --ks-pass pass:android --out out/Probe.apk out/aligned.apk
md5sum out/Probe.apk
