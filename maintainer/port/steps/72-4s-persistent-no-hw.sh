#!/bin/sh
# Phase 4s: no persistent apps for hardware pipa does not have (system, system_ext).
#
# Each of these apps is android:persistent="true" (checked in the donor manifests), so it runs in its own process from
# boot to shutdown, but it cannot do anything on pipa:
#   com.android.nfc  (system/priv-app/NfcNci)     pipa has no NFC controller and no NFC HAL
#   com.android.se   (system/app/SecureElement)   no secure element (no NFC eSE, no SIM UICC)
#   com.qti.qcc      (system_ext/app/QCC)         Qualcomm client-insights telemetry
# Estimate 40-70 MB PSS together (notes/cloud/APPS-RAM.md). Their privapp/allow-list entries stay: PackageManager skips
# entries of packages that are not installed. The library com.android.nfc_extras stays (optional for other apps).
# Before a release: `pm list features | grep -i nfc` on the tablet must be empty (DEVICE-CHECKS.md section 7).
set -eu
. "$PORT/lib.sh"
STEP=4s

for d in system/system/priv-app/NfcNci system/system/app/SecureElement system_ext/app/QCC; do
    [ -d "$T/$d" ] || die "$d not found (other donor?)"
    rm -rf "$T/$d"
    echo "removed $d"
done
set_layer "$STEP"
