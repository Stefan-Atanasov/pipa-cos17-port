#!/bin/sh
# Phase 4l: Google Quick Share works next to OPPO file sharing (BUGS-TODO 53; system, system_ext).
#
# * my_product/etc/permissions/oplus_google_cn_gms_features.xml: no feature cn.google.services. With it, GMS treats
#   the tablet as a China device and disables all its Quick Share components (com.google.android.gms.nearby.sharing.*).
#   com.google.android.feature.services_updater stays.
# * pipa_port service.sh + config.prop: QUICK_SHARE turns the 13 core Quick Share components on once (dirty flash:
#   GMS disabled them before); OSHARE_ROLLBACK removes an App Market update of OShare at boot, so the patched ROM
#   copy from 4k stays in use. Both `pm` calls work from the pipa_port domain (runcon test, no rule needed).
# Tested live 2026-11-02 on pt23 (binds + zygote restart): Quick Share opens; GMS kept the 13 core parts and turned
# its 6 Samsung/migration screens off again by itself. OShare tablet -> OPPO phone without the interconnect: worked (4k).
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=4l

GF=$T/system/my_product/etc/permissions/oplus_google_cn_gms_features.xml
need_grep 'com.google.android.feature.services_updater' "$GF"
replace_once "$GF" '    <feature name="cn.google.services" />\n' ''
forbid_grep 'cn.google.services' "$GF"

SE=$T/system_ext
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place: owner, mode and label stay
done
need_grep 'quick_share_set' "$SE/pipa_port/service.sh"
need_grep '^OSHARE_ROLLBACK=1' "$SE/pipa_port/config.prop"
set_layer "$STEP"
