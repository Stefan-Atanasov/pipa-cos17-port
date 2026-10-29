#!/bin/sh
# Build cryptoeng.jar (CryptoEngShim, BUGS-TODO B8) for /system_ext/pipa_port/. Needs JDK 17+ and the Android SDK
# (platform android-37.0, build-tools 37.0.0), like helper/build.sh.
#
#   sh maintainer/cryptoeng/build.sh      -> maintainer/cryptoeng/cryptoeng.jar
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
JAR=$SDK/platforms/android-37.0/android.jar
BT=$SDK/build-tools/37.0.0
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
mkdir "$OUT/classes" "$OUT/dex"
javac --release 17 -Xlint:-options -cp "$JAR" -d "$OUT/classes" "$HERE/CryptoEngShim.java"
"$BT/d8" --release --min-api 35 --lib "$JAR" --output "$OUT/dex" "$OUT"/classes/*.class
python3 -I -c "
import sys, zipfile
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as z:
    i = zipfile.ZipInfo('classes.dex', (2026, 1, 1, 0, 0, 0)); i.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(i, open(sys.argv[1], 'rb').read())
" "$OUT/dex/classes.dex" "$HERE/cryptoeng.jar"
md5sum "$HERE/cryptoeng.jar"
