#!/bin/sh
# Step 9t (BUGS 201, tester report "still only 2 floating windows" on pt177; user 2026-11-27 "do that if needed"):
# remove the OPPO feature oplus.software.wms.panorama_work_station.
# The feature turns on OPPO's "panorama" multi-window manager (Find N / OPPO Pad Free-Flow windows). On a tablet with
# RAM <= 8 GB (OplusPanoramaWorkBranchUtil.sRamSizeSupport false: pipa) OPPO uses its reduced "fold" variant:
# hasFoldPanoramaWorkFeature() = tablet and not sRamSizeSupport, so FlexibleWindowUtils.getMaxFlexibleTaskNum() = 2
# (PANORAMA_MAX_FLEXIBLE_TASK_NUM_FOR_LOW_RAM_TABLET). The 3rd floating window minimises the oldest
# (FlexibleTaskController.handleExceedLimitFlexibleTask). Step 9j (policy maxWinNum 4) is not read on that path.
# Without the feature OPPO uses its classic floating window path (as on its tablets without the feature):
# FlexibleWindowManagerService.getMaxWinNum() = policy maxWinNum (4, step 9j).
# Live test 2026-11-27 (pt177, bind mount): 4 floating windows at the same time (log "maxWinNum:4", no exceed);
# split view, Recents (classic card grid, tap the app icon for Floating window / Split View) and Pipa Helper in a
# floating window work; no crash.
set -eu
. "$PORT/lib.sh"
STEP=9t
echo "== 9t no panorama workstation (4 floating windows)"

X=$T/system/my_product/etc/extension/com.oplus.oplus-feature.xml
[ -f "$X" ] || die "$X not found"
need_grep '"oplus.software.wms.panorama_work_station"' "$X"
replace_once "$X" '<oplus-feature name="oplus.software.wms.panorama_work_station"/>' \
'<!-- pipa port 9t: oplus.software.wms.panorama_work_station removed (8 GB tablet: 2 floating windows) -->'
forbid_grep '<oplus-feature name="oplus.software.wms.panorama_work_station"/>' "$X"
python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$X" || die "XML broken"
need_grep 'maxWinNum="4"' "$T/system_ext/oplus/sys_flexiblewindow_policy_list.xml"
