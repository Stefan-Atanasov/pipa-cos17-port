#!/bin/sh
# Step 8v (2026-11-22, BUGS 170 + 174): Xiaomi pen apps as on HyperOS, and the double tap to wake switch.
# * BUGS 170: Notein and StarNote read the pen buttons as page down / page up (stock HyperOS has no pen .kl, so the
#   page keys arrive near and away from the screen). Since kernel hi12 a near press was a stylus button only.
#   - kernel walt-hi16: pipa_pen_buttons near_mode 1 = a near press is the page key (held for the press, no OPPO click,
#     no long action). Default 0 = hi15.
#   - helper 3.0: Pen buttons > "Apps made for the Xiaomi pen" (preset Notein, StarNote; Global pipa_pen_apps) and
#     "Page down / page up in all apps" (Global pipa_pen_near_all). GameKeeper's foreground listener (no polling) sets
#     Global pipa_pen_near; service.sh pen_near_check writes it to the kernel.
#   - framework PipaAppIdentity (step 3o compiles it): new profile "pad6" (Xiaomi/Xiaomi/pipa/pipa/23043RP34C), the
#     default for Notein (its key map and palm detector need MANUFACTURER xiaomi) and StarNote. Helper label fix:
#     "ROM device (OPPO OPD2515)" (it said "Real device (Xiaomi Pad 6)", but apps see OPD2515, step 6f).
# * BUGS 174: touchshim.jar (step 4o copies it) handles OPPO touch node 1 (double tap to wake) -> Xiaomi touch mode 14.
#   The running IOplusTouch is the copy built into halshims.jar (4r): checked below (sha256 of TouchService.java).
#   Before, the ColorOS switch did nothing and the vendor power HAL default (/sys/touchpanel/double_tap = 1) stayed on.
# The files come in with the earlier copy steps (helper/out, port-rom, 3o, 4o); this step checks them and sets a new
# layer so that the package cache takes the new helper.
set -eu
. "$PORT/lib.sh"
STEP=8v
SE=$T/system_ext
need_grep 'pen_near_check()' "$SE/pipa_port/service.sh"
need_grep 'pipa_pen_near' "$SE/pipa_port/service.sh"
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" \
    "$T/system/system/framework/framework.jar" "$HERE/../port-rom/pipa_port/touchshim.jar" "$SE/pipa_port/touchshim.jar" \
    "$SE/pipa_port/halshims.jar" "$HERE/touchshim/TouchService.java" <<'PY'
import sys, zipfile, hashlib
src, img, fw, shim_src, shim_img, hal_img, ts_src = sys.argv[1:]
def dex(p):
    z = zipfile.ZipFile(p)
    return b''.join(z.read(n) for n in z.namelist() if n.endswith('.dex'))
def md5(p):
    return hashlib.md5(open(p, 'rb').read()).hexdigest()
d = dex(src)
assert b'pipa_pen_near' in d and b'pipa_pen_apps' in d, 'helper without the pen near mode (helper 3.0)'
assert md5(src) == md5(img), 'image helper %s != helper/out %s' % (md5(img), md5(src))
f = dex(fw)
assert b'pad6' in f and b'23043RP34C' in f, 'framework.jar: PipaAppIdentity without the Xiaomi Pad 6 profile (3o ran with old source?)'
assert md5(shim_src) == md5(shim_img), 'image touchshim %s != port-rom %s' % (md5(shim_img), md5(shim_src))
# the HAL host (4r, HAL_SHIMS has touch) serves IOplusTouch with its own copy of TouchService; until 2026-11-25 it
# was an old build, so the dt2w switch still did nothing on pt152 (live fix: rebuilt halshims.jar)
hs = zipfile.ZipFile(hal_img).read('touchservice.sha256').decode().strip()
assert hs == hashlib.sha256(open(ts_src, 'rb').read()).hexdigest(), 'halshims.jar built from an old TouchService.java: sh maintainer/halshims/build.sh'
print('helper 3.0, framework pad6 profile, touchshim and halshims touch (node 1) in the image', md5(src), md5(shim_img), md5(hal_img))
PY
set_layer "$STEP"
