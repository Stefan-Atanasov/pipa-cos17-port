#!/bin/sh
# Step 8s (2026-11-21, BUGS 164/165): helper 2.8 + animation style waits for Apply.
# * BUGS 164 (user): the "Live blur" Quick Settings tile (7x BlurTile) is gone; the switch stays in Pipa Helper >
#   Effects (global pipa_live_blur, read by service.sh blur_check as before).
# * BUGS 165 (user): Effects > Animation style restarted the launcher at once (service.sh anim_check force-stopped it
#   on every pipa_anim_level change) and threw the user out of the helper. anim_check now only sets
#   persist.sys.oplus.anim_level; the launcher restarts with the helper's Apply (pipa_fx_restart, fx_check) or, for a
#   config override, at the first check after boot. Helper toast "Tap Apply ...".
# * User 2026-11-21: Animation style offers Rich (2) and Smooth (3, stock) only; a stored Light (4) falls back to the
#   default in anim_check. A note on the page says a reboot applies a style fully. Reset to defaults no longer restarts
#   anything by itself: it shows Apply and Reboot like a style change.
# The helper APK and service.sh come in with the earlier copy steps (helper/out, port-rom); this step checks them and
# sets a new layer so that the package cache takes the new helper.
set -eu
. "$PORT/lib.sh"
STEP=8s
SE=$T/system_ext
need_grep 'ANIM_FIRST=1' "$SE/pipa_port/service.sh"
need_grep 'case $want in 2|3) ;;' "$SE/pipa_port/service.sh"
need_grep 'launcher animation tier -> $want (applied with the helper' "$SE/pipa_port/service.sh"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
z = zipfile.ZipFile(src)
d = b''.join(z.read(n) for n in z.namelist() if n.endswith('.dex'))
assert b'Lcom/port/pipa/helper/BlurTile;' not in d, 'helper still has BlurTile'
assert b'pipa_live_blur' in d, 'helper without the Effects live blur switch'
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, 'image helper %s != helper/out %s' % (b, a)
print('helper 2.8 (no Live blur tile) in the image', a)
PY
set_layer "$STEP"
