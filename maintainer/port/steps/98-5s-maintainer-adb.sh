#!/bin/sh
# Phase 5s (OPTIONAL, runs only with PORT_MAINTAINER_ADB=1): adb works right after a CLEAN flash, for the maintainer's
# own test builds (2026-11-05: an unattended clean-flash test of beta7). NEVER publish such a build.
#
# * product/etc/security/adb_keys (the target of the /adb_keys link; label adb_keys_file from plat_file_contexts):
#   the public key of this build host (~/.android/adbkey.pub of the owner, or PORT_ADB_PUBKEY=<file>). adbd trusts it
#   like /data/misc/adb/adb_keys, so no "Allow USB debugging" tap is needed.
# * product build.prop persist.sys.usb.config=mtp,adb and ro.pipa.maintainer_adb=1. ColorOS sets USB to charge-only at
#   the first setup (seen 2026-11-05: MTP for 8 s, then off), so service.sh also puts global adb_enabled=1 when
#   ro.pipa.maintainer_adb=1 (the property is only in such builds; service.sh comes from port-rom in step 2e).
# ro.adb.secure stays 1: only the holder of the matching private key gets in. A release build (without the variable)
# has neither change.
#OPTIONAL: PORT_MAINTAINER_ADB
#NEEDS: "$PORT/lib.sh"
set -eu
. "$PORT/lib.sh"
STEP=5s

if [ "${PORT_MAINTAINER_ADB:-0}" != 1 ]; then
    echo "skipped (PORT_MAINTAINER_ADB is not 1): no adb key, USB debugging off at the first boot"
    exit 0
fi
K=${PORT_ADB_PUBKEY:-/home/${OWNER%%:*}/.android/adbkey.pub}
[ -s "$K" ] || die "no adb public key: $K"
D=$T/product/etc/security
[ -d "$D" ] || die "no $D"
install -o 0 -g 0 -m 644 "$K" "$D/adb_keys"
setfattr -n security.selinux -v u:object_r:adb_keys_file:s0 "$D/adb_keys"
echo "product/etc/security/adb_keys <- $K ($(awk '{print $NF}' "$K"))"
BP=$T/product/etc/build.prop
forbid_grep "^persist.sys.usb.config=" "$BP"
printf '\n# pipa port 5s (maintainer test build only): USB debugging on at the first boot\npersist.sys.usb.config=mtp,adb\nro.pipa.maintainer_adb=1\n' >> "$BP"
need_grep "^persist.sys.usb.config=mtp,adb" "$BP"
need_grep "^ro.pipa.maintainer_adb=1" "$BP"
need_grep "ro.pipa.maintainer_adb" "$T/system_ext/pipa_port/service.sh"
echo "WARNING: maintainer build with adb key + USB debugging: never publish"
