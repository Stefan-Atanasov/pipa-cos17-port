#!/bin/sh
# Phase 8m (2026-11-20, BUGS 160/161): ColorOS SAU app updates (built-in OPPO apps such as MSP com.heytap.htms, which
# the OPPO account needs at >= 2.1.4; the ROM has 1.11.7).
# * SAUAppService exits when the system runs without dm-verity ("verity is disable, only exit"), and SAU sends
#   productName = ro.product.name (pipa). maintainer/sau/patch_sau.py: only the app update service skips the verity
#   gate (opex system patches stay blocked: they overwrite system parts and target the real MediaTek OPD2515), and
#   productName = Build.MODEL (OPD2515, as on stock OPPO). Same approach as toraidl/coloros_port (patch the check in the
#   app, no global verity/lock spoof). Same-size in-place dex patch: OPPO's signature block stays; oat/ removed.
# * versionCode 17000023 -> 17999023 (7l family): the server offers no SAU self-update, which would drop the patch;
#   service.sh PATCHED_ROLLBACK also lists com.oplus.sau.
# * Patched apps keep their 17999xx versionCodes and the boot rollback (7l), so SAU offers nothing newer for them.
set -eu
. "$PORT/lib.sh"
STEP=8m
D=$T/system_ext/app/SystemAppUpdateService
A=$D/SystemAppUpdateService.apk
[ -f "$A" ] || die "no $A"
python3 -I "$HERE/sau/patch_sau.py" "$A" "$R/sau.patched.apk"
python3 -I "$HERE/oshare/bump_version.py" "$R/sau.patched.apk" "$R/sau.final.apk" 17000023 17999023
cat "$R/sau.final.apk" > "$A"   # in place: owner, mode and SELinux label stay
rm -f "$R/sau.patched.apk" "$R/sau.final.apk"
rm -rf "$D/oat"
md5sum "$A"
need_grep 'com.oplus.sau' "$T/system_ext/pipa_port/service.sh"
set_layer "$STEP"
