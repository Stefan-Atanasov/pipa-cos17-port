#!/bin/sh
# Build pipa helper without Gradle: aapt2 link -> javac -> d8 -> zipalign -> apksigner.
# Output: helper/out/PipaHelper.apk. Needs JDK 21 and ~/Android/Sdk (build-tools 37.0.0, android-37.0).
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/37.0.0
JAR=$SDK/platforms/android-37.0/android.jar
KS=keys/pipa-helper.jks
# Signing key password: env KSPASS, else keys/keystore.pass next to the key (both private, never shared: with the key
# anyone can sign helper updates the ROM accepts). A new key is generated when keys/ is empty (fresh port kit).
if [ -z "${KSPASS:-}" ]; then
    if [ -f keys/keystore.pass ]; then KSPASS=$(cat keys/keystore.pass)
    else mkdir -p keys; KSPASS=$(head -c 18 /dev/urandom | base64); echo "$KSPASS" > keys/keystore.pass; fi
fi

rm -rf out && mkdir -p out/classes out/dex out/gen
if [ ! -f "$KS" ]; then
    keytool -genkeypair -keystore "$KS" -storepass "$KSPASS" -keypass "$KSPASS" -alias pipa \
        -keyalg RSA -keysize 3072 -validity 36500 -dname "CN=pipa port helper" >/dev/null
fi

"$BT/aapt2" compile --dir res -o out/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o out/base.apk --java out/gen out/res.zip
javac --release 17 -Xlint:-options -cp "$JAR" -d out/classes $(find src out/gen -name '*.java')
"$BT/d8" --release --min-api 35 --lib "$JAR" --output out/dex $(find out/classes -name '*.class')
cp out/base.apk out/unsigned.apk
(cd out/dex && zip -q -X ../unsigned.apk classes.dex 2>/dev/null) || python3 - <<'EOF'
import zipfile
with zipfile.ZipFile("out/unsigned.apk", "a") as z:
    z.write("out/dex/classes.dex", "classes.dex")
EOF
"$BT/zipalign" -f -p 4 out/unsigned.apk out/aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass "pass:$KSPASS" --out out/PipaHelper.apk out/aligned.apk
"$BT/apksigner" verify out/PipaHelper.apk
md5sum out/PipaHelper.apk
