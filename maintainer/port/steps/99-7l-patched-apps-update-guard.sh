#!/bin/sh
# Step 7l (BUGS 127, user 2026-11-17: "protection to all our apps so SOTA and store updates don't break them"):
# an App Market / SOTA update of a system app installs into /data/app and wins over the ROM copy, so the port's dex
# patches are lost (and a dirty flash does not bring them back). Same guard as 5r (OShare) for every other patched app:
# raise android:versionCode in place (maintainer/oshare/bump_version.py: same-size zip entry, signing block untouched),
# so stores see no newer version and Android drops an older /data update at boot. Safety net: pipa_port service.sh
# PATCHED_ROLLBACK removes any /data update of these packages at boot.
# Patched by: SystemUI 3b/4e/4v/9w, Settings 4u/6n/7m, OplusLauncher 4e/4v/9w, OplusEyeProtect 3f, Wallpapers 5t, IPeManager 2p,
# Battery 5v. 2026-11-17 (review): bump_version.py finds android:versionCode by its resource id, so Battery (37 = also
# its targetSdk) is bumped too; a donor versionCode at or above the target now stops the build (pick a higher target).
set -eu
. "$PORT/lib.sh"
STEP=7l
command -v libdeflate-gzip >/dev/null || die "libdeflate-gzip missing (package libdeflate)"
AAPT=$(ls "${ANDROID_HOME:-/home/stefan/Android/Sdk}"/build-tools/*/aapt2 | tail -1)
echo "== 7l versionCode guard for patched system apps"
# apk path | new versionCode (family 17 + 999 block, above any 17.x store build)
while read -r A NEW; do
    [ -n "$A" ] || continue
    F=$T/$A
    [ -f "$F" ] || die "missing $F"
    OLD=$("$AAPT" dump badging "$F" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)
    [ -n "$OLD" ] || die "no versionCode in $F"
    [ "$OLD" -lt "$NEW" ] || die "$A: donor versionCode $OLD >= guard $NEW (raise the guard value in 7l)"
    if python3 -I "$HERE/oshare/bump_version.py" "$F" "$R/bumped.apk" "$OLD" "$NEW"; then
        cat "$R/bumped.apk" > "$F"          # in place (cat >): owner, mode and SELinux label stay
        rm -f "$R/bumped.apk"; rm -rf "$(dirname "$F")/oat"
        GOT=$("$AAPT" dump badging "$F" 2>/dev/null | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)
        [ "$GOT" = "$NEW" ] || die "$A: versionCode $GOT after bump, expected $NEW"
        echo "bumped  $A $OLD -> $NEW"
    else
        rm -f "$R/bumped.apk"
        echo "NOTE    $A: versionCode $OLD not bumped (value not unique); boot rollback covers it"
    fi
done <<'EOF'
system_ext/priv-app/SystemUI/SystemUI.apk 179999
system_ext/priv-app/Settings/Settings.apk 17999000
system_ext/priv-app/OplusLauncher/OplusLauncher.apk 179999012
system_ext/app/OplusEyeProtect/OplusEyeProtect.apk 17999001
system/my_stock/priv-app/Wallpapers/Wallpapers.apk 17999031
system/my_product/priv-app/IPeManager/IPeManager.apk 17999000
system_ext/app/Battery/Battery.apk 17999037
EOF
set_layer "$STEP"                                # new layer: early.sh clears the package parse cache
