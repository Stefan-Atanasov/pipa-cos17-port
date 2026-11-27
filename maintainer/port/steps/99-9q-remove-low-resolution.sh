#!/bin/sh
# Step 9q (user 2026-11-27): Settings > Display > Screen resolution Low is removed. Step 9g (OPPO's forced-size
# resolution switch, pt164-pt172) moved to maintainer/port/drafts/. Reason: at Low, OPPO code that mixes the panel size
# and the forced size breaks things (boot logo zoom 205, depth effect 207, square icon in the close animation 208; 203
# and 206 needed patches 9n/9p: moved to drafts too, user 2026-11-27 "like in 9.3"). A real Low display mode (QTI vendor.display.window_rect,
# BUGS 196) broke the lock screen and transitions: OPPO's resolution code is tied to 1800x2880.
# * pipa_port/service.sh: a tablet left on Low goes back to High once after the update (wm size reset, density
#   272/296/328 -> 340/370/410, OPPO setting 2 -> 3). SELinux: pipa_port may find window_service (secilc exit 0, 76).
# * pipa_port.rc: OPPO's persist.sys.display.density/.screen_resolution/.user_density leftovers are cleared after the
#   persist props load (480 made SystemUI, launcher, lock screen clocks and Settings scale wrong; live test 2026-11-27:
#   deleted + reboot = fixed).
set -eu
. "$PORT/lib.sh"
STEP=9q
echo "== 9q Screen resolution Low removed: back to High once"

SE=$T/system_ext
need_grep 'screen resolution Low removed' "$SE/pipa_port/service.sh"
need_grep 'setprop persist.sys.display.density ""' "$SE/etc/init/pipa_port.rc"
grep -q 'pipa_port window_service' "$SE/etc/selinux/system_ext_sepolicy.cil" || die "pipa_port window_service rule not in the policy"
if grep -q '^ro.oplus.resolution.low=' "$T/product/etc/build.prop" 2>/dev/null; then die "9g props still in product/etc/build.prop"; fi
