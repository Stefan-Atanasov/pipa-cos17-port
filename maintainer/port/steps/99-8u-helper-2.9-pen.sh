#!/bin/sh
# Step 8u (2026-11-21, BUGS 167/169): helper 2.9 + pen defaults for kernel walt-hi15.
# * Default long press 380 -> 500 ms (helper DEFAULT, pen_keys.sh PEN_DEFAULT, service.sh fallback; the kernel default
#   is 500 too): with hi15 a press that starts with the pen away turns into a near press when the pen reaches the
#   screen before the long press fires, so a longer long press leaves more time to bring the pen down.
# * service.sh resets global pipa_pen_test (the helper's Pen buttons test screen flag) at boot: a reboot with that
#   screen open sent every pen action to the closed test screen (BUGS 167).
# The helper APK and the pipa_port scripts come in with the earlier copy steps (helper/out, port-rom); this step checks
# them and sets a new layer so that the package cache takes the new helper.
set -eu
. "$PORT/lib.sh"
STEP=8u
SE=$T/system_ext
need_grep 'pipa_pen_test was left at 1 -> 0' "$SE/pipa_port/service.sh"
need_grep 'c="1 500"' "$SE/pipa_port/service.sh"
need_grep 'PEN_DEFAULT="1 500 ' "$SE/pipa_port/pen_keys.sh"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
z = zipfile.ZipFile(src)
d = b''.join(z.read(n) for n in z.namelist() if n.endswith('.dex'))
assert b'1 500 quicknote screenshot none none none none' in d, 'helper without the 500 ms default'
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, 'image helper %s != helper/out %s' % (b, a)
print('helper 2.9 (pen long press 500 ms) in the image', a)
PY
set_layer "$STEP"
