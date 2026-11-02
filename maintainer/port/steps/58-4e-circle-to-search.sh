#!/bin/sh
# Phase 4e: Circle to Search on a long press of the gesture bar (BUGS-TODO 49, user wish in the public bug doc
# 2026-11-02; system and system_ext).
#
# OplusLauncher starts Google's Circle to Search (Settings: circle_to_search_enable_navi) only when
# isExp (global build) && hasSystemFeature("com.google.android.feature.CONTEXTUAL_SEARCH"), as on global ColorOS.
# * maintainer/cts/patch_launcher_cts.py: removes the isExp test (2 nops in place, platform signature kept).
# * my_product/etc/permissions/pipa.feature.contextual_search.xml declares the feature (Pixels and global OPPO
#   devices have it). The Google app (com.google.android.googlequicksearchbox, Play Store) must be installed.
# * The launcher's hidden-nav-handle path also tests isExp and the OPPO feature
#   oplus.software.navbar_hidden_contextual_search (pipa.feature.navbar_contextual_search.xml below).
# * maintainer/cts/patch_systemui_assist.py: SystemUI AssistManager.startAssist returns on CN builds unless the OPPO
#   test mode (sIsClosedSuperFirewall) is on; the patch removes that return (1 nop in place).
# The assistant that the long press starts is pipa helper 0.8 (step 4g).
#NEEDS: "$HERE/cts/patch_launcher_cts.py" "$HERE/cts/patch_systemui_assist.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=4e

L=$T/system_ext/priv-app/OplusLauncher/OplusLauncher.apk
[ -f "$L" ] || die "no $L"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/cts/patch_launcher_cts.py" "$L" "$R/OplusLauncher.cts.apk" 2>&1 | grep -v DEBUG
cat "$R/OplusLauncher.cts.apk" > "$L"   # in place: owner, mode and SELinux label stay
rm -rf "$T/system_ext/priv-app/OplusLauncher/oat"

U=$T/system_ext/priv-app/SystemUI/SystemUI.apk
[ -f "$U" ] || die "no $U"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/cts/patch_systemui_assist.py" "$U" "$R/SystemUI.cts.apk" 2>&1 | grep -v DEBUG
cat "$R/SystemUI.cts.apk" > "$U"
rm -rf "$T/system_ext/priv-app/SystemUI/oat"

P=$T/system/my_product/etc/permissions
SIB=$P/oplus.feature.control_cn_gms.xml
[ -f "$SIB" ] || die "no $SIB (label template)"
F=$P/pipa.feature.contextual_search.xml
cp -p "$SIB" "$F"                       # owner, mode; label below
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
cat > "$F" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port 4e: Circle to Search (OplusLauncher checks this feature) -->
<permissions>
    <feature name="com.google.android.feature.CONTEXTUAL_SEARCH" />
</permissions>
XML
echo "added   my_product/etc/permissions/${F##*/}"
F=$P/pipa.feature.navbar_contextual_search.xml
cp -p "$SIB" "$F"
setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux "$SIB")" "$F"
cat > "$F" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port 4e: Circle to Search from the hidden gesture bar (OplusHideNavHandleController checks this feature) -->
<oplus-config>
    <oplus-feature name="oplus.software.navbar_hidden_contextual_search" />
</oplus-config>
XML
echo "added   my_product/etc/permissions/${F##*/}"
set_layer "$STEP"
