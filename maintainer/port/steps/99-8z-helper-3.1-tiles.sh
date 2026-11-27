#!/bin/sh
# Step 8z (2026-11-25, BUGS 172): helper 3.1 Quick Settings tiles as on HyperOS.
# * Dolby Atmos tile (DolbyTile): on = Dolby, off = the effect used before Dolby on this output (Xiaomi Sound or
#   Original), as on HyperOS; remembered per output like a choice in MiSound (DolbyKeeper.setUserEffect). 3.1.1:
#   the "off" effect (live-tested: Xiaomi Sound -> Dolby -> Xiaomi Sound). ColorOS's own Dolby tile stays off (Settings disables it without the
#   OPPO Dolby features; our Dolby runs through MiSound + the helper).
# * Hotspot tile (HotspotTile): TetheringManager.startTethering/stopTethering with the Personal hotspot settings.
#   ColorOS hides its hotspot tile on Wi-Fi only tablets (OplusHotspotTile.isAvailable: isTabletWifi).
#   Needs TETHER_PRIVILEGED (privileged): added to the helper's privapp list here.
# * Long press: TilePrefsActivity -> MiSound / Personal hotspot settings.
# Live test 2026-11-25 (pt152, bind mount + zygote restart): Dolby tile none <-> dolby; Hotspot tile on (wlan2
# TETHERED, 2437 MHz) and off.
# The helper APK comes in with the earlier copy step (helper/out); this step checks it and sets a new layer so that
# the package cache takes the new helper.
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=8z
python3 -I - "$HERE/../helper/out/PipaHelper.apk" "$T/system/system/priv-app/PipaHelper/PipaHelper.apk" <<'PY'
import sys, zipfile, hashlib
src, img = sys.argv[1:]
d = b''.join(zipfile.ZipFile(src).read(n) for n in zipfile.ZipFile(src).namelist() if n.endswith('.dex'))
for s in (b'DolbyTile', b'HotspotTile', b'TilePrefsActivity', b'startTethering'):
    assert s in d, 'PipaHelper.apk without %s (helper 3.1)' % s.decode()
a = hashlib.md5(open(src, 'rb').read()).hexdigest(); b = hashlib.md5(open(img, 'rb').read()).hexdigest()
assert a == b, 'image helper %s != helper/out %s' % (b, a)
print('helper 3.1 (Dolby + Hotspot tiles) in the image', a)
PY
X=$T/system/system/etc/permissions/privapp-permissions-pipa-helper.xml
[ -f "$X" ] || die "no $X"
forbid_grep 'TETHER_PRIVILEGED' "$X"
replace_once "$X" '        <permission name="android.permission.REBOOT" />\n' \
    '        <permission name="android.permission.REBOOT" />\n        <permission name="android.permission.TETHER_PRIVILEGED" />\n'
need_grep 'android.permission.TETHER_PRIVILEGED' "$X"
grep -n 'permission name' "$X"
set_layer "$STEP"
