#!/bin/sh
# Phase 2a: the two "easy" runtime pieces leave pipa_core / power-tune (notes/PHASE2-ROM-INTEGRATION.md
# A4, A9).
#
# A4 system/app/FaceUnlock: the legacy socket face client (com.pipa.faceunlock, R4). Confirmed on
#    beta5-1c (2026-10-22): /data/system/facehal_socket never exists; the facehal-rs AIDL HAL is
#    used and power-tune disables the app every boot.
# A9 AOD off for good (maintainer decision 2026-10-22, LCD panel): the AOD feature flags are
#    commented out in my_product's display feature list, so Settings hides AOD as on other LCD
#    ColorOS devices. pipa_core's AodBacklightDaemon (and power-tune's AOD freeze, B3) then have
#    nothing to do; remove them from the modules once this image is verified.
#
# Old layer script: build_beta5_2a.sh
set -eu
. "$PORT/lib.sh"

echo "== A4 drop FaceUnlock"
[ -d "$T/system/system/app/FaceUnlock" ] || { echo "FaceUnlock not found"; exit 1; }
rm -rf "$T/system/system/app/FaceUnlock"

echo "== A9 AOD feature off"
F=system/my_product/etc/permissions/oplus.product.display_features.xml
for f in aod_support aod_prevent_burn_support lcd_aod_mode; do
    replace_once $F "    <oplus-feature name=\"oplus.software.display.$f\"/>\n" \
        "    <!-- pipa port: AOD off (LCD) <oplus-feature name=\"oplus.software.display.$f\"/> -->\n"
done

