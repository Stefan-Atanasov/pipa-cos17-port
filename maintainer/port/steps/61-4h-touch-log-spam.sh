#!/bin/sh
# Phase 4h: no log lines on every touch from ColorOS parts that pipa lacks (BUGS-TODO 39, public bug doc; system only).
#
# maintainer/logspam/patch_logspam.py, in place in the stored dex (same size; jars carry no signature):
# * oplus-framework.jar UAHAdaptHelper.getAidlService: OPPO's urcc HAL does not exist on pipa; each touch did a
#   service manager lookup and logged "getAidlService uah urcc service =  null" (6 per swipe). Now: false at once.
# * oplus-services.jar: Osense "osenseSetSceneAction: action is not SCENE_SPECIAL_REQUEST" (3 per swipe) and
#   WindowStateExtImpl "isForceUpdateWallpaperScale" (2 per swipe, live wallpaper): log call removed.
# * services.jar PowerManagerService "userActivityNoUpdateLocked: groupId=..." (4 per swipe): log call removed.
# * system_ext/etc/build.prop: persist.sys.assert.panic=false. Nothing in the ROM set it, and OPPO's SystemUI reads it
#   with default true: all SystemUI debug logs ran (about 50 lines per notification shade pull). Developers can still
#   `setprop persist.sys.assert.panic true` (a set value wins over this default). pt21, 80 swipes: 6903 -> 2443 lines.
# Measured 2026-11-02 on pt20: 80 swipes, scratchpad spam.sh. oplus-framework is a boot jar: the prebuilt boot image
# no longer matches and odrefresh compiles one into /data on the first boot (as for framework.jar in step 3o).
#NEEDS: "$HERE/logspam/patch_logspam.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=4h

F=$T/system/system/framework
for j in oplus-framework oplus-services services; do
    echo "== $j.jar"
    "$HERE/jar-edits/venv/bin/python" -I "$HERE/logspam/patch_logspam.py" "$F/$j.jar" "$R/$j.jar" 2>&1 | grep -v DEBUG
    cat "$R/$j.jar" > "$F/$j.jar"   # in place (cat >): owner, mode and SELinux label stay
    rm -f "$R/$j.jar"
    # services.jar has a prebuilt odex in the donor; it no longer matches the jar. odrefresh compiles all system_server
    # jars into /data/misc/apexdata anyway since step 3o (checked on pt21), so the prebuilt files are not used.
    for o in "$F/oat"/*/"$j".*; do if [ -e "$o" ]; then rm -v "$o"; fi; done
done
BP=$T/system_ext/etc/build.prop
forbid_grep '^persist.sys.assert.panic=' "$BP"
{ cat "$BP"; printf '\n# pipa port 4h: OPPO debug logs off (SystemUI reads this with default true)\npersist.sys.assert.panic=false\n'; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode
set_layer "$STEP"
