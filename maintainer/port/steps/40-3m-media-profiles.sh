#!/bin/sh
# Phase 3m: media profiles path (BUGS-TODO 30), product only.
#
# The donor system/build.prop sets media.settings.xml=/vendor/etc/media_profiles_vendor.xml. The pinned vendor has no
# such file (only media_profiles.xml, media_profiles_V1_0.xml, media_profiles_kona.xml, all the same). The first
# zygote64 then aborts at each boot in CamcorderProfile preload (MediaProfiles CHECK(fopen) failed) and starts again;
# the second one uses media_profiles_kona.xml.
# * product/etc/build.prop: media.settings.xml=/vendor/etc/media_profiles_kona.xml (product loads after system).
set -eu
. "$PORT/lib.sh"

BP=$T/product/etc/build.prop

echo "== 30: media.settings.xml=/vendor/etc/media_profiles_kona.xml"
if grep -q "^media.settings.xml=" "$BP"; then echo "product build.prop already sets media.settings.xml"; exit 1; fi
[ -f "$T/vendor/etc/media_profiles_kona.xml" ] || die "vendor/etc/media_profiles_kona.xml missing"
{ cat "$BP"; printf '%s\n' "# pipa port 3m (BUGS-TODO 30): the system value points to a file that the vendor does not have" "media.settings.xml=/vendor/etc/media_profiles_kona.xml"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label kept
tail -2 "$BP"
