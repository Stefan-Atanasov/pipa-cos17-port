#!/bin/sh
# Phase 8o (2026-11-20, BUGS 160): MSP (com.heytap.htms, "HeyTap mobile services") 1.11.7 -> 2.3.0.
# The OPPO account app (App Market update 10.01.002) checks the device through MSP's sysintegrity kit and needs MSP
# versionCode >= 2010400. The donor OPD2515 ships 1.11.7 (1110700), and neither SAU (8m: the server lists no MSP for
# OPD2515) nor App Market offer an update: "Device environment not secure". 2.3.0 (2030016) is the system copy of a CN
# ColorOS 17 phone (user's PMX110, /product/app/MSPService), same OPPO certificate (bc8692b5, lineage eda63435) and
# sharedUserId android.uid.htmsenv. Live test 2026-11-20 (pt142 + adb install): account login works.
# extractNativeLibs=false (24 stored arm64 libs): the old lib/ folder goes; oat/ is not shipped.
# Blob (not in git, 99 MB): $P/blobs/MSPService-2.3.0.apk  md5 83d3c7ebfd75054173ac251fdc1af875 (backup: /mnt/reference/pipa/port-work/blobs/)
#NEEDS: "$P/blobs/MSPService-2.3.0.apk"
set -eu
. "$PORT/lib.sh"
STEP=8o
NEW=$P/blobs/MSPService-2.3.0.apk
[ "$(md5sum < "$NEW" | cut -c1-32)" = 83d3c7ebfd75054173ac251fdc1af875 ] || die "MSP blob md5 mismatch"
D=$T/system/my_stock/app/MSPService
[ -f "$D/MSPService.apk" ] || die "no $D/MSPService.apk"
cat "$NEW" > "$D/MSPService.apk"   # in place: owner, mode and SELinux label stay
rm -rf "$D/lib" "$D/oat"
ls -la "$D"
set_layer "$STEP"
