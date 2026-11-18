#!/bin/sh
# Phase 7w (beta9 clean flash 2026-11-18, BUGS 136): helper 2.1, MiSound settings page shows Dolby again.
#
# * MiSound's page (h/i.java getEnabledEffect) reads android.media.audiofx.MiSound.getEnabled = effect param 25
#   only. The helper switched the MiSound effect with plain AudioEffect.setEnabled, so param 25 stayed 1 (MiSound's
#   boot default). Dolby on + flag 1 -> "both of enabled, force return misound": the page showed "Xiaomi Sound" and
#   wrote misound at each open; the helper undid it (engine stayed Dolby). Seen only after a clean flash.
# * helper 2.1: every MiSound switch (holder apply + temporary handle) also writes param 25, as MiSound.setEnabled.
# * Step 4g copies helper/out/PipaHelper.apk; this step checks that it is 2.1 and sets the layer (package cache).
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=7w
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = zipfile.ZipFile(src).read('classes.dex')
assert b"MiSound flag" in d, "PipaHelper.apk: no MiSound flag (2.1 or newer needed)"
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, f'image helper {b} != helper/out {a} (step 4g ran with an older APK?)'
print('helper 2.1 in the image', a)
PY
set_layer "$STEP"
