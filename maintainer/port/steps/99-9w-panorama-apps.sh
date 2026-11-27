#!/bin/sh
# Step 9w (BUGS 217, tester report 2026-11-27 on v10.1 = pt181: "frame drop when opening another app, and the floating
# window overlaps Recents instead of minimising"): the launcher and SystemUI have their own copies of OPPO's panorama
# RAM test. 9v lowered only the system_server one (oplus-services), so on pt181 system_server ran tablet panorama while
# * OplusLauncher (com.oplus.quickstep.panorama.a.w(), RAM rounded up to GB > 8) said "panoramic not supported": in
#   Recents the floating windows stayed on top of the cards (reproduced with a real swipe-up-and-hold, kgest);
# * SystemUI WM Shell (FullscreenTaskWindowDecorController.sRamSizeSupport, totalMem / 2^30 > 8.0) took the fold
#   variant (OplusPanoramaWorkBranchAnimController.isFoldPanoramaWorkEnable) for the shell transitions.
# maintainer/flexwin/patch_panorama_ram_apk.py lowers both to 6 (one constant each, same-size in-place dex patch, OPPO
# signature block kept, like 4e). Device sweep 2026-11-27: of the 14 APK/JARs that mention panorama, only these two
# and oplus-services test RAM for it (Settings, OplusFlexibleWindowUI, oplus-framework, DeviceHub, games: no).
# Live test (pt181 + bind mounts): Recents shows OPPO's panorama layout (floating windows as cards next to their app),
# SystemUI log "RamSizeSupporttrue", four-finger gestures and launches work, 0 crashes. 7l keeps guarding both APKs.
#NEEDS: "$HERE/flexwin/patch_panorama_ram_apk.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=9w
echo "== 9w launcher + SystemUI panorama RAM test 8 -> 6 GB (same as 9v in system_server)"

for A in system_ext/priv-app/OplusLauncher/OplusLauncher.apk system_ext/priv-app/SystemUI/SystemUI.apk; do
    F=$T/$A
    [ -f "$F" ] || die "no $F"
    "$HERE/jar-edits/venv/bin/python" -I "$HERE/flexwin/patch_panorama_ram_apk.py" "$F" "$R/panorama.apk" 2>&1 | grep -v DEBUG
    [ -s "$R/panorama.apk" ] || die "patch failed for $A"
    cat "$R/panorama.apk" > "$F"          # in place (cat >): owner, mode and SELinux label stay
    rm -f "$R/panorama.apk"
    rm -rf "$(dirname "$F")/oat"
    unzip -tq "$F" >/dev/null || die "$A: zip test failed"
    md5sum "$F"
done

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
