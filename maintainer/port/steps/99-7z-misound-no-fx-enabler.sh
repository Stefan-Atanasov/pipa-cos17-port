#!/bin/sh
# Phase 7z (2026-11-19, BUGS 145): MiSound without the beta4 "PipaFxEnabler" thread.
#
# * beta4 added classes2.dex to MiSound.apk with a stub miui.os.Build. Its static initializer starts a thread that,
#   3 s after each MiSound process start, opens priority 0 handles on session 0 for DAP and the MiSound effect,
#   enables both and keeps them while the process lives. Stock HyperOS has no such code; the helper (DolbyKeeper)
#   does the boot job the stock way.
# * Effects: one MiSound DSP reset (audible blip) 3 s after MiSound starts (its screen opened, or at boot), the
#   MiSound effect enabled in the chain with Dolby selected, and the helper holders without control while MiSound runs.
# * patch_fxenabler.py: the Thread.start() call becomes 3 nops (pattern checked, same entry size, the porter's v3
#   signing block stays; Android reads only the certificate of a system-partition APK, as for IPeManager in 2p).
# * Live test 2026-11-19 (bind mount, Spotify playing): MiSound screen open 1 reset -> 0; Dolby <-> Xiaomi Sound
#   switches the effects and the helper stores the choice; the page shows the right effect after a restart.
# * New layer: the package cache must not keep the old parse (EROFS mtimes are 0).
#NEEDS: "$HERE/misound/patch_fxenabler.py"
set -eu
. "$PORT/lib.sh"
STEP=7z
MS=$T/system/system/priv-app/MiSound
MS_B4_MD5=bf1505bbcba06b317a2158253a8aa3a6   # beta4 MiSound.apk
md5=$(md5sum "$MS/MiSound.apk" | cut -d' ' -f1)
[ "$md5" = "$MS_B4_MD5" ] || echo "NOTE MiSound.apk $md5 is not the beta4 file: the pattern-checked patch decides"
python3 -I "$HERE/misound/patch_fxenabler.py" "$MS/MiSound.apk" "$R/MiSound.patched.apk"
cat "$R/MiSound.patched.apk" > "$MS/MiSound.apk"   # in place (cat >): owner, mode and SELinux label stay
rm -rf "$MS/oat"
md5sum "$MS/MiSound.apk"
set_layer "$STEP"
