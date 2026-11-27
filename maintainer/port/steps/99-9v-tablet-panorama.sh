#!/bin/sh
# Step 9v (BUGS 216, user 2026-11-27 "lets do 1 ... ship as ota for everyone on v10"): OPPO's full tablet panorama
# (Find N / OPPO Pad multi-window) on the 8 GB pipa. Replaces 9t (pt180 removed panorama_work_station: 4 floating
# windows, but the four-finger gestures need panorama and stopped working on v10).
# * OplusPanoramaWorkBranchController.onAmsReady: sRamSizeSupport = totalMem / 2^30 > 8.0. pipa reports 7.41 GiB, so
#   ColorOS took the "low RAM tablet" fold variant (getMaxFlexibleTaskNum() = 2: the 3rd floating window minimised the
#   oldest). maintainer/flexwin/patch_panorama_ram.sh lowers the threshold to 6.0 GiB (one constant): the tablet
#   panorama path, as on OPPO tablets with more RAM. The feature oplus.software.wms.panorama_work_station stays (donor).
# Live test 2026-11-27 (pt180 + bind mounts, kgest pinch): 5 floating windows (OPPO "..." menu > Floating window);
# four-finger pinch out: 3 floating -> 3-way split, 2 floating -> 2-way split, 1 floating -> full screen; pinch in:
# split -> floating, full screen -> floating; OPPO's own tip "Switch between Floating Window and Split View" shows.
# 0 crashes, 0 lmkd kills, MemAvailable 3.8 GB with 5 windows.
# * system_ext/etc/build.prop: ro.pipa.port.layer=9v (changed jar: early.sh clears the package cache).
#NEEDS: "$HERE/flexwin/patch_panorama_ram.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"
set -eu
. "$PORT/lib.sh"
STEP=9v
echo "== 9v tablet panorama on 8 GB (oplus-services RAM threshold 8.0 -> 6.0 GiB)"

X=$T/system/my_product/etc/extension/com.oplus.oplus-feature.xml
need_grep '<oplus-feature name="oplus.software.wms.panorama_work_station"/>' "$X"
forbid_grep 'pipa port 9t' "$X"

J=$T/system/system/framework/oplus-services.jar
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/flexwin/patch_panorama_ram.sh" "$J" "$R/oplus-services.jar.new"
cat "$R/oplus-services.jar.new" > "$J"   # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/oplus-services.jar.new"
if ls "$T/system/system/framework/oat"/*/oplus-services.* >/dev/null 2>&1; then die "prebuilt oat for oplus-services exists"; fi
md5sum "$J"   # on the pt180 jar (5c applied): bc9e5016d533a97034e90694f7668ee1

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
