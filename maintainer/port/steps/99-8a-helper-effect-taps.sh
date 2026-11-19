#!/bin/sh
# Phase 8a (2026-11-19, BUGS 146): helper 2.4, a tap on an effect in MiSound is never undone.
#
# * Helper 1.8 (BUGS 108) took each effect change within 3 s of a MiSound ACTIVITY_RESUMED for MiSound's own
#   cold-start default and undid it. That also hit real taps: a quick tap after the screen opened, or after the
#   return from the equalizer page (also a resume). MiSound's page then showed the effect that was undone
#   ("Xiaomi Sound" with Dolby on).
# * The cause of BUGS 108 is gone: MiSound wrote misound at each open only while its flag (param 25) was 1 (BUGS 136,
#   step 7w). Test 2026-11-19 (pt129): 5 cold starts after a force-stop, no tap: MiSound writes nothing.
# * helper 2.4: the 3 s guard is removed; the foreground and output-change checks (1.6) stay.
# * Live test (bind mount): quick tap after a cold open and after the equalizer page = stored; the page shows the
#   right effect after a cold start (Dolby Atmos and Xiaomi Sound).
# * Step 4g copies helper/out/PipaHelper.apk; this step checks that it is 2.4 and sets the layer (package cache).
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=8a
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = zipfile.ZipFile(src).read('classes.dex')
assert b"(temporary handle)" in d, "PipaHelper.apk: older than 2.3"
assert b"MiSound usage events" not in d, "PipaHelper.apk: still has the 3 s open guard (2.4 or newer needed)"
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, f'image helper {b} != helper/out {a} (step 4g ran with an older APK?)'
print('helper 2.4 in the image', a)
PY
set_layer "$STEP"
