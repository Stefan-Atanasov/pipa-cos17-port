#!/bin/sh
# Phase 4k: OPPO file sharing (OShare) tablet -> phone works without the interconnect (BUGS-TODO 53; system only).
#
# Without the interconnect, OShare checks the receiver over BLE with an HMAC key from the TEE (ICryptoeng,
# "GukManager"). Only genuine OPPO TEEs can derive that key; on pipa the call throws (our CryptoEngShim from 3a does
# not know OPPO's secret): "TAInterfaceException: Unable to get data from cryptoeng" -> "BleClient: verify failed" ->
# "Recipient's transfer channel occupied". oshare/patch_oshare.py makes b0.y() return true only on that exception
# (same-size dex edit in place, OPPO signature block kept, like 2p IPeManager). A real TEE answer is not changed.
# Cost (user decision 2026-11-02): the tablet does not check that the receiver is a genuine OPPO device; the
# transfer stays encrypted.
#NEEDS: "$HERE/oshare/patch_oshare.py" "$HERE/ipe-fluid/patch_ipemanager.py"
set -eu
. "$PORT/lib.sh"
STEP=4k
OSHARE_STOCK_MD5=90ecf99c7c8f600670a53c25312f89e2   # C.06 (17.0.0.103) OShare 17.2.36

O=$T/system/my_stock/priv-app/OShare
[ -f "$O/OShare.apk" ] || die "OShare.apk missing: $O"
md5=$(md5sum "$O/OShare.apk" | cut -d' ' -f1)
[ "$md5" = "$OSHARE_STOCK_MD5" ] || echo "NOTE OShare.apk $md5 is not C.06: the pattern-checked patch decides; test sharing"
python3 -I "$HERE/oshare/patch_oshare.py" "$O/OShare.apk" "$R/OShare.patched.apk"
cat "$R/OShare.patched.apk" > "$O/OShare.apk"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/OShare.patched.apk"
rm -rf "$O/oat"                                  # the prebuilt odex no longer matches the dex
md5sum "$O/OShare.apk"
set_layer "$STEP"                                # new layer: early.sh clears the package parse cache
