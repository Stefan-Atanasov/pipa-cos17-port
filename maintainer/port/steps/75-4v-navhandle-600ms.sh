#!/bin/sh
# Phase 4v: Circle to Search starts after a 600 ms hold on the gesture bar, not 800 ms (BUGS-TODO 49, user wish
# 2026-11-02; system_ext only).
#
# * system_ext/priv-app/OplusLauncher/OplusLauncher.apk: the launcher times the nav-handle long press with its own
#   copy of OPLUS NavigationGestureDetector (C.07: com.android.quickstep.r4, used by OplusCuiInputConsumer), with a
#   constant 800 ms threshold. No setting or DeviceConfig key feeds it.
# * system_ext/priv-app/SystemUI/SystemUI.apk: the same detector in SystemUI (handle long-press animation), also
#   600 ms, so the animation and the trigger agree.
# * maintainer/cts/patch_navhandle_longpress.py changes the constant in place (platform signature kept). It runs on
#   the APKs that 4e already changed. Tested live 2026-11-03 (bind mount of both): 650 and 700 ms holds start Circle
#   to Search (3/3, before 0/3), 500 ms does not (0/2).
# * system_ext/etc/build.prop: ro.pipa.port.layer=4v (changed APKs: early.sh clears the package cache).
#NEEDS: "$HERE/cts/patch_navhandle_longpress.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=4v
MS=600

for a in OplusLauncher SystemUI; do
    A=$T/system_ext/priv-app/$a/$a.apk
    [ -f "$A" ] || die "no $A"
    echo "== $a: nav-handle long press $MS ms"
    "$HERE/jar-edits/venv/bin/python" -I "$HERE/cts/patch_navhandle_longpress.py" "$A" "$R/$a.lp.apk" "$MS" 2>&1 | grep -v DEBUG
    cat "$R/$a.lp.apk" > "$A"   # in place: owner, mode and SELinux label stay
    rm -f "$R/$a.lp.apk"
    rm -rf "$T/system_ext/priv-app/$a/oat"
    md5sum "$A"
done
# on pt32 (C.07): OplusLauncher 95de0da74ac25cd4afb8eab755730af8, SystemUI d561570262e8a98f2b8eb6ff3f426897

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
