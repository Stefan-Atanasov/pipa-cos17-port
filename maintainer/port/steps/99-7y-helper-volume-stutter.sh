#!/bin/sh
# Phase 7y (2026-11-19, BUGS 144): helper 2.3, no audio dropout on a volume step or when the sound settings open.
#
# * The Dolby speaker tuning (speaker_volume_low/high, switch at 2/3 of the music volume) went through a temporary
#   priority 0 DAP handle. It took control from the helper's DAP holder; control back ran apply() again.
# * apply() wrote MiSound's flag (param 25, step 7w) at each control change, also with no change. Each write makes
#   the MiSound effect reset and reload its DSP setup (MiSound_updateState reset=1): a short dropout. The sound
#   settings page also opens its own effect handles (it reads params 5 and 25): 5 resets at each open.
# * helper 2.3: the tuning goes through the holder when it has control (stock DolbyEffectController uses its own
#   handle); the flag is read first and written only when it differs.
# * Live test 2026-11-19 (bind mount, MiSound stopped first): 8 tuning switches = 8 control losses + 8 resets on
#   2.2, 0 + 0 on 2.3; sound settings open = 5 resets on 2.2, 0 on 2.3.
# * Step 4g copies helper/out/PipaHelper.apk; this step checks that it is 2.3 and sets the layer (package cache).
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=7y
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = zipfile.ZipFile(src).read('classes.dex')
assert b"(temporary handle)" in d, "PipaHelper.apk: tuning through a temporary handle only (2.3 or newer needed)"
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, f'image helper {b} != helper/out {a} (step 4g ran with an older APK?)'
print('helper 2.3 in the image', a)
PY
set_layer "$STEP"
