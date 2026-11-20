#!/bin/sh
# Phase 8g (2026-11-20, BUGS 150): device identity per game, chosen by the user in Pipa Helper > Games.
# * Step 3o compiles maintainer/propspoof/src/.../PipaAppIdentity.java into framework.jar. Since 8g it also reads
#   Global "pipa_app_identity" ("pkg=key;..."; "real" = the real device) once per app start, only for apps that are
#   not system apps. No entry = the port default list (3o).
# * helper 2.5 GameIdentity.java has a copy of the profile keys and the default list (for the UI): both must match.
set -eu
. "$PORT/lib.sh"
STEP=8g
J=$T/system/system/framework/framework.jar
python3 -I - "$J" "$HERE/propspoof/src/com/android/internal/util/pipa/PipaAppIdentity.java" \
    "$HERE/../helper/src/com/port/pipa/helper/GameIdentity.java" <<'PY'
import re, sys, zipfile
jar, fw, hp = sys.argv[1:]
z = zipfile.ZipFile(jar)
assert any(b'pipa_app_identity' in z.read(n) for n in z.namelist() if n.endswith('.dex')), \
    'framework.jar: PipaAppIdentity without the user choice (3o ran with old source?)'
f = open(fw).read(); h = open(hp).read()
keys_fw = set(re.findall(r'case "(\w+)": return', f))
keys_hp = set(re.findall(r'\{ "(\w+)", "[^"]+" \}', h))
assert keys_fw == keys_hp, 'profile keys differ: framework %s, helper %s' % (keys_fw ^ keys_hp, '')
gm = f[f.index('Object[][] GAMES'):]; gm = gm[:gm.index('};')]
pk_fw = set(re.findall(r'"([a-z][\w.]+)"', gm))
dl = h[h.index('DEFAULTS = {'):]; dl = dl[:dl.index('};')]
pk_hp = set(re.findall(r'"([a-z][\w.]+\.[\w.]+)", "\w+"', dl)) - {'com.netflix.mediaclient', 'com.google.android.apps.photos'}
assert pk_fw == pk_hp, 'game lists differ: %s' % (pk_fw ^ pk_hp)
print('framework.jar has the user choice; %d profiles and %d games match the helper' % (len(keys_fw), len(pk_fw)))
PY
set_layer "$STEP"
