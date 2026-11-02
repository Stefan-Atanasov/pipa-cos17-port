#!/bin/sh
# Build original Java sources only. Do not read or package donor jars.
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
ANDROID=$SDK/platforms/android-37.0/android.jar
D8=$SDK/build-tools/37.0.0/d8
mkdir -p out/classes out/dex
rm -f out/classes/pipa/touch/*.class out/dex/classes*.dex
javac --release 17 -cp "$ANDROID" -d out/classes TouchService.java TouchHost.java
"$D8" --release --min-api 35 --lib "$ANDROID" --output out/dex out/classes/pipa/touch/*.class
python3 - <<'PY'
from pathlib import Path
import zipfile
out = Path('../../port-rom/pipa_port/touchshim.jar')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(Path('out/dex').glob('classes*.dex')):
        info = zipfile.ZipInfo(p.name, (1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, p.read_bytes())
print(out)
PY
