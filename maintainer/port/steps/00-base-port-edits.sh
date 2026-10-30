#!/bin/sh
# Base step ("beta5"): a C.06-based port: donor OS side + curated port edits + beta4 vendor/odm.
#
# port.sh has already extracted the donor (system with the my_* mount contents folded in, system_ext,
# product) and the pinned beta4 vendor/odm images into $T/{system,system_ext,product,vendor,odm}.
# This step does what the old build_beta5.sh did after that:
#  * applies the curated port edits (c06-vs-beta4/PORT-EDITS.tsv: carried beta4 files, removed donor
#    files, merged build.prop files, the beta4 SELinux block ...) with apply_port_edits.py;
#  * IEngineer fix in oplus-services.jar: C.06 hangs system_server with ro.adb.secure=1
#    (OplusEngineerFwService waits for a HAL that pipa does not have). The jar must be the stock C.06 jar.
#
# apply_port_edits.py reads the files that it carries from the beta4 source tree $PORT_OVERLAY_SRC
# (default: COS17/port-overlay, the frozen beta4 files; the full root-extracted beta4 tree port-work/roundtrip/src
# also works). It has system/ and system_ext/. Set PORT_OVERLAY_SRC when you start port.sh to use another folder.
#
# On a NEW donor this step is EXPECTED to stop (md5 of the stock jar, PORT-EDITS rows): that is the
# safety net. Read the message, regenerate the fix from the new donor's file, update the md5, run again.
#
# Old layer script: build_beta5.sh
#NEEDS: "$HERE/apply_port_edits.py" "$HERE/c06-vs-beta4/PORT-EDITS.tsv" "$PORT_OVERLAY_SRC/system" "$PORT_OVERLAY_SRC/system_ext" "$MOD/tools/patch_framework.sh"
set -eu
. "$PORT/lib.sh"
: "${PORT_OVERLAY_SRC:?PORT_OVERLAY_SRC is not set (port.sh sets it)}"
[ -d "$PORT_OVERLAY_SRC/system" ] && [ -d "$PORT_OVERLAY_SRC/system_ext" ] || die "overlay source has no system/ and system_ext/: $PORT_OVERLAY_SRC"

echo "== apply port edits (overlay source $PORT_OVERLAY_SRC)"
python3 -I "$HERE/apply_port_edits.py" "$HERE/c06-vs-beta4/PORT-EDITS.tsv" "$PORT_OVERLAY_SRC" "$T"

echo "== IEngineer fix in oplus-services.jar (C.06 hangs system_server with ro.adb.secure=1)"
J="$T/system/system/framework/oplus-services.jar"
# patch_framework.sh finds its site by pattern and stops on any surprise, so it also works on a new donor.
# On C.06 the known md5s are a regression check (stock 2175feb9 -> 7afeadb1).
in_md5=$(md5sum < "$J" | cut -c1-32)
PATCH=engineer sh "$MOD/tools/patch_framework.sh" "$J" "$W/eng.jar"
cat "$W/eng.jar" > "$J"; rm -f "$W/eng.jar"                        # same inode: label, owner, mode kept
out_md5=$(md5sum < "$J" | cut -c1-32)
if [ "$in_md5" = 2175feb9d4b03eb2859e73e71cfb854d ]; then
    [ "$out_md5" = 7afeadb12583df3b1fdd92490e2e76cc ] || die "C.06: engineer patch gave an unexpected jar ($out_md5)"
else
    echo "NOTE new donor jar $in_md5 -> $out_md5 (pattern-checked by patch_framework.sh; test the boot)"
fi
