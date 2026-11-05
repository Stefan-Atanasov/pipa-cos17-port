#!/bin/sh
# Phase 5r: the OPPO App Market cannot replace the patched OShare (BUGS-TODO 74, user 2026-11-05, beta7).
#
# The App Market tracks com.coloros.oshare (market.db pkgMd5) and can install a newer OPPO-signed version into
# /data/app: that update replaces the 4k patch (file sharing without the TEE peer check). Of the APKs the port patches
# (SystemUI, Settings, Launcher, IPeManager, Eye Protect, OShare) only OShare is on the market's list.
# * oshare/bump_version.py raises android:versionCode 17002036 -> 17999036 (versionName stays 17.2.36) in place:
#   the manifest is deflated again with libdeflate, the saved bytes go into the local extra field, all offsets and
#   OPPO's signing block stay (as the 4k dex patch: Android does not verify APKs on system partitions). The market
#   then sees no newer 17.x version, and Android drops an older /data/app update at boot.
# * Needs `libdeflate-gzip` on the build host.
#NEEDS: "$HERE/oshare/bump_version.py"
set -eu
. "$PORT/lib.sh"
STEP=5r

command -v libdeflate-gzip >/dev/null || die "libdeflate-gzip missing (package libdeflate)"
O=$T/system/my_stock/priv-app/OShare
[ -f "$O/OShare.apk" ] || die "OShare.apk missing: $O"
python3 -I "$HERE/oshare/bump_version.py" "$O/OShare.apk" "$R/OShare.bumped.apk" 17002036 17999036
python3 -I - "$R/OShare.bumped.apk" <<'PY'
import sys, zipfile, struct
z = zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None
m = z.read('AndroidManifest.xml'); assert m.count(b'\x08\x00\x00\x10' + struct.pack('<I', 17999036)) == 1
PY
cat "$R/OShare.bumped.apk" > "$O/OShare.apk"     # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/OShare.bumped.apk"
rm -rf "$O/oat"
md5sum "$O/OShare.apk"
set_layer "$STEP"                                # new layer: early.sh clears the package parse cache
