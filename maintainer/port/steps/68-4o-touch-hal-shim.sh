#!/bin/sh
# Phase 4o: OPPO touch HAL replacement (BUGS-TODO 51; system_ext).
#
# No vendor.oplus.hardware.touch.IOplusTouch on pipa: ColorOS game touch settings (Games/COSA), edge and corner
# rejection and the panel direction did nothing. touchshim.jar (maintainer/touchshim, own code, AIDL V2) maps the
# OPPO nodes to the Xiaomi touch modes of the nt36532 driver through xiaomi_touch_ioctl: 245 game mode -> 0,
# 243 tap -> 2, 25 swipe -> 4 (aim), 24 smoothness -> 3 reversed (tolerance), 251/252/IME grip -> 7 edge filter,
# 5 direction -> 8. Ranges from the COSA callers (1..100, 0 = reset; corner 1..3). Separate jar from the 4m charger.
#NEEDS: "$ROM/pipa_port/touchshim.jar" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=4o
SE=$T/system_ext
# new file: same owner, mode and SELinux label as the charger jar next to it
install -o 0 -g 0 -m 644 "$ROM/pipa_port/touchshim.jar" "$SE/pipa_port/touchshim.jar"
setfattr -n security.selinux -v "$(getfattr -n security.selinux --only-values "$SE/pipa_port/chargershim.jar")" "$SE/pipa_port/touchshim.jar"
# The service name gets the type of the charger and cryptoeng shims (oplus_absent_service, declared in the pipa vendor
# policy). The system_ext policy already lets pipa_port add it, and system_server finds the charger through it. The
# registrar's intermediate name pipa.touch.shim stays default_android_service, as pipa.charger.shim.
C=$SE/etc/selinux/system_ext_service_contexts
forbid_grep 'IOplusTouch' "$C"
need_grep '(allow pipa_port oplus_absent_service (service_manager (add)))' "$SE/etc/selinux/system_ext_sepolicy.cil"
printf 'vendor.oplus.hardware.touch.IOplusTouch/default u:object_r:oplus_absent_service:s0\n' >> "$C"   # same inode
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"   # in place; the touch shim start block is in it
need_grep 'pipa.touch.TouchHost' "$SE/pipa_port/service.sh"
set_layer "$STEP"
