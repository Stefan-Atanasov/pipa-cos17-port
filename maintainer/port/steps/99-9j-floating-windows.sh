#!/bin/sh
# Step 9j (BUGS-TODO 201, tester report 2026-11-26, user: "max value possible"): up to 4 floating windows (was 2; the
# 3rd one minimised the oldest).
# Code (oplus-services FlexibleWindowManagerService.getMaxWinNum): panorama workstation on -> 4 (tablet < 800 dp,
# pipa) or 5; else the policy file maxWinNum; no value -> 3. The panorama workstation needs RAM > 8 GiB
# (OplusPanoramaWorkBranchController.onAmsReady), so on pipa (8 GB) the donor file value 2 applies, with Rich and
# Smooth animations alike (the animation level only matters on phones: isSupportDualFlexibleTask).
# CORRECTION 2026-11-27: wrong. On pipa the feature oplus.software.wms.panorama_work_station gives OPPO's low-RAM
# tablet panorama path with a cap of 2 (getMaxFlexibleTaskNum); this file was not read. Step 9t removes the feature.
# * system_ext/oplus/sys_flexiblewindow_policy_list.xml: scenario 1 maxWinNum 2 -> 4 (OPPO's own value for this
#   screen class). The panorama workstation itself stays off (stock RAM rule).
set -eu
. "$PORT/lib.sh"
STEP=9j
echo "== 9j floating windows: max 4"

X=$T/system_ext/oplus/sys_flexiblewindow_policy_list.xml
[ -f "$X" ] || die "no $X"
need_grep 'maxWinNum="2"' "$X"
sed 's/maxWinNum="2"/maxWinNum="4"/' "$X" > "$R/flexpolicy.9j.xml"
need_grep 'maxWinNum="4"' "$R/flexpolicy.9j.xml"
cat "$R/flexpolicy.9j.xml" > "$X"   # in place: owner, mode and SELinux label stay
rm -f "$R/flexpolicy.9j.xml"
set_layer "$STEP"
