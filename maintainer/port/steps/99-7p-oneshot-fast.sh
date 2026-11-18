#!/bin/sh
# Phase 7p: lock -> home clock "one shot" animation also at the Fast animation tier 3 (user 2026-11-18).
#
# * OplusLauncher (s6.h via ii.h.j) and SystemUI (OneShotAnimState.isOneShotEnabled: animLevelOverride > 2) turn the
#   one-shot off at persist.sys.oplus.anim_level 3 and 4. The port's Fast tier is 3 (helper Animations tile), so the
#   lock screen clock never flew to the home clock widget. Live test 2026-11-18 at tier 2 (Slow): works with the
#   home "Clock widget" + "Sync with Lock screen clock". At tier 3 the rest of Fast stays as it is: only the one-shot
#   check is changed (oneshot/patch_oneshot_fast.py). Tier 4 keeps it off (SystemUI limit 3).
# * 2026-11-18 (pt120): also the launcher one-shot spring timing picker keyguardservice.b.f (tier 3: 850 -> 510-637 ms,
#   user: "plain fast movement"; tier 2 is fluid but laggy elsewhere) -> tier-2 timing; wallpaper zoom stays off.
# * 2026-11-18 (pt121): the clock flight itself is drawn by the KeyguardPersonalityClocks plugin (in SystemUI). Its
#   isLowGaussianLevel (anim_level >= 3) skips the clock render pipeline, so at tier 3 the one-shot ended after ~20 ms
#   (clock cut, no flight; logcat onUnlockReady -> onAnimationEnd 32 ms, tier 2: 800 ms). Limit 3 -> 4 (as SystemUI).
# * Same-size in-place dex edits; oat dirs removed (dexopt again on first boot). Runs after 7l (versionCode guard).
#NEEDS: "$HERE/oneshot/patch_oneshot_fast.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=7p
for spec in launcher:priv-app/OplusLauncher systemui:priv-app/SystemUI clocks:app/KeyguardPersonalityClocks; do
    which=${spec%%:*}; sub=${spec#*:}; dir=${sub#*/}
    A=$T/system_ext/$sub/$dir.apk
    [ -f "$A" ] || die "no $A"
    "$HERE/jar-edits/venv/bin/python" -I "$HERE/oneshot/patch_oneshot_fast.py" "$which" "$A" "$R/$dir.7p.apk" \
        > "$R/7p.log" 2>&1 || { grep -v DEBUG "$R/7p.log"; die "$which patch failed"; }
    grep -v DEBUG "$R/7p.log"
    grep -q "$which: one-shot at tier 3 patched" "$R/7p.log" || die "$which: no patch line"
    cat "$R/$dir.7p.apk" > "$A"   # in place: owner, mode and SELinux label stay
    rm -f "$R/$dir.7p.apk" "$R/7p.log"
    rm -rf "$T/system_ext/$sub/oat"
done
set_layer "$STEP"
