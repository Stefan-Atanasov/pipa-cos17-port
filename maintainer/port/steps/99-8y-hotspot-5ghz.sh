#!/bin/sh
# Step 8y (2026-11-25, BUGS 171): Settings > Personal hotspot > AP band offers 5 GHz again.
# pipa's vendor Wi-Fi HAL does not support getUsableChannels (NOT_SUPPORTED), so OPPO's OplusSoftapP2pBandControl
# gets empty channel lists and canUseSoftap5GBand() returns false. maintainer/wifi5g/patch_softap5g.sh drops the
# country-list condition of OPPO's own "cannot get channel list from driver" fallback (the country reads as null here),
# so 5 GHz follows WifiManager.is5GHzBandSupported(). OPPO's 2.4 GHz-only region check stays in front of it.
# Live test 2026-11-25 (pt152, bind mount + zygote restart): the 5 GHz choice appears; the hotspot ran on 5180 MHz
# (ch 36, 80 MHz, Wi-Fi 5) next to the Wi-Fi client connection.
# The prebuilt odex/vdex of the jar are deleted: ART rejects them for the changed dex (as for 3o/4h) and compiles on
# the device.
#NEEDS: "$HERE/wifi5g/patch_softap5g.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"
set -eu
. "$PORT/lib.sh"
STEP=8y
echo "== 8y oplus-wifi-service: hotspot 5 GHz without the driver channel list (BUGS 171)"
J=$T/system_ext/framework/oplus-wifi-service.jar
[ -f "$J" ] || die "missing $J"
[ "$(md5sum < "$J" | cut -d' ' -f1)" = 2dc260a9e9738738ca8971b5cbf6045c ] || die "$J: unexpected md5 (not the C.07 jar)"
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/wifi5g/patch_softap5g.sh" "$J" "$R/oplus-wifi-service.jar.new"
cat "$R/oplus-wifi-service.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-wifi-service.jar.new"
[ "$(md5sum < "$J" | cut -d' ' -f1)" = d3b24a4402db3b4b4df03912d5a73df7 ] || die "$J: patched md5 differs from the live-tested jar"
for f in "$T"/system_ext/framework/oat/*/oplus-wifi-service.odex* "$T"/system_ext/framework/oat/*/oplus-wifi-service.vdex*; do
    [ -e "$f" ] || continue
    rm -f "$f"; echo "removed ${f#$T/}"
done
set_layer "$STEP"
