#!/bin/sh
# Build the pipa HAL shims (own Java sources only; no donor jars are read or packaged).
# Output: port-rom/pipa_port/halshims.jar. Needs JDK 21, Android SDK platform android-37.0 and build-tools 37.0.0.
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
ANDROID=$SDK/platforms/android-37.0/android.jar
D8=$SDK/build-tools/37.0.0/d8
rm -rf out && mkdir -p out/classes out/dex
# the touch shim (step 4o) is built into this host too (key "touch"); its source stays in maintainer/touchshim
javac --release 17 -Xlint:all -Werror -Xlint:-options -Xlint:-deprecation -cp "$ANDROID" -d out/classes \
    $(find src -name '*.java' | sort) ../touchshim/TouchService.java
"$D8" --release --min-api 35 --lib "$ANDROID" --output out/dex $(find out/classes -name '*.class' | sort)
python3 -I - <<'PY'
from pathlib import Path
import zipfile
out = Path('../../port-rom/pipa_port/halshims.jar')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as z:   # stored: steps can grep the jar (need_grep)
    for p in sorted(Path('out/dex').glob('classes*.dex')):
        info = zipfile.ZipInfo(p.name, (1980, 1, 1, 0, 0, 0))
        z.writestr(info, p.read_bytes())
print(out)
PY
