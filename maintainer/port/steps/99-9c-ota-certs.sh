#!/bin/sh
# Step 9c (2026-11-25, BUGS 193): the ROM trusts our OTA key, so update_engine accepts our A/B payloads
# (maintainer/ota/make_payload.sh). Without /system/etc/update_engine/update-payload-key.pub.pem, update_engine takes the
# key from /system/etc/security/otacerts.zip (-> /my_engineering/etc/security/otacerts.zip, OPPO's certificate).
# This step replaces that zip with maintainer/ota/keys/otacerts.zip (our x509 certificate only; the private key stays in
# maintainer/ota/keys/, never in git or a port kit). Side effect wanted: OPPO OTA packages no longer verify (never
# install the donor OTA, GOTCHAS).
#NEEDS: "$HERE/ota/keys/otacerts.zip"
set -eu
. "$PORT/lib.sh"
STEP=9c
Z=$T/system/my_engineering/etc/security/otacerts.zip
[ -f "$Z" ] || die "no $Z"
SRC=$HERE/ota/keys/otacerts.zip
python3 -I -c "import sys, zipfile; n = zipfile.ZipFile(sys.argv[1]).namelist(); sys.exit(0 if n == ['pipa-ota.x509.pem'] else 1)" "$SRC" \
    || die "$SRC is not our otacerts.zip (one entry pipa-ota.x509.pem)"
cat "$SRC" > "$Z"
cmp -s "$SRC" "$Z" || die "otacerts.zip copy differs"
echo "otacerts.zip = pipa OTA certificate ($(md5sum < "$SRC" | cut -c1-8))"
