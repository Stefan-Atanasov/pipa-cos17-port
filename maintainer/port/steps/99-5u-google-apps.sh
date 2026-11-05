#!/bin/sh
# Phase 5u (user 2026-11-05): Play Store, Gboard and the Google app (Circle to Search) on the first boot.
#
# * system_ext/pipa_port/apps/<package>/{base.apk,split_*.apk,version}: stable versions from Play, pulled from the
#   tablet on 2026-11-05 (input folder port-inputs/apps-5u, sha256 list there; Google signatures checked with
#   apksigner). service.sh (5u part, from port-rom in 2e) installs each one once per install as a normal app or update
#   when the installed version is older, retries every 60 s, and makes Gboard the default keyboard. Play Store then
#   updates them. The ROM's own Play Store is only the old updater stub (my_product GooglePlayServicesUpdater 82275402),
#   which needed the OPPO App Market to install the real one.
# * service.sh also sets the pipa helper as the assistant (4g, Circle to Search) after that install, and checks again
#   every 5 minutes while the Google app is missing (on a clean flash the boot-time check found no Google app).
# * rules_5u_system_ext.cil: the AOSP selinux_check_access set for pipa_port. `pm install <file>` from the service
#   needs it (the cmd client checks system_server's read access to the file); without it every path-based install
#   failed (beta7 clean flash: no SukiSU manager). secilc exit 0, neverallow 76.
# * service.sh makes Gboard the default with `settings put` (enabled_input_methods + default_input_method): `ime`
#   finds no input_method service in the pipa_port domain. Only over Sogou or no keyboard (dirty flash keeps the
#   user's keyboard).
# Inputs: about 500 MB (super has room: 6.8 of 9.1 GB used at pt57).
#NEEDS: "$HERE/../../port-inputs/apps-5u/SHA256SUMS" "$HERE/sepolicy/rules_5u_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=5u

SEL=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SEL/$f" ] || continue
    forbid_grep "pipa port 5u" "$SEL/$f"
    { cat "$SEL/$f"; cat "$HERE/sepolicy/rules_5u_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SEL/$f"; rm -f "$R/$f.new"   # same inode
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5u" "$SEL/system_ext_sepolicy.cil"

IN=$HERE/../../port-inputs/apps-5u
[ -f "$IN/SHA256SUMS" ] || die "no $IN/SHA256SUMS"
(cd "$IN" && sha256sum -c --quiet SHA256SUMS) || die "apps-5u: sha256 mismatch"
A=$T/system_ext/pipa_port/apps
[ ! -e "$A" ] || die "system_ext/pipa_port/apps exists already"
mkdir "$A"
for pkg in com.android.vending com.google.android.inputmethod.latin com.google.android.googlequicksearchbox; do
    [ -f "$IN/$pkg/base.apk" ] && [ -s "$IN/$pkg/version" ] || die "apps-5u: $pkg incomplete"
    mkdir "$A/$pkg"
    cp "$IN/$pkg"/*.apk "$IN/$pkg/version" "$A/$pkg/"
    echo "added   $pkg $(cat "$IN/$pkg/version") ($(ls "$IN/$pkg" | grep -c '\.apk$') apk)"
done
chown -R 0:0 "$A"
find "$A" -type d -exec chmod 755 {} +
find "$A" -type f -exec chmod 644 {} +
find "$A" -exec setfattr -n security.selinux -v u:object_r:system_file:s0 {} +
need_grep 'bundled_apps()' "$T/system_ext/pipa_port/service.sh"
need_grep '^BUNDLED_APPS=1' "$T/system_ext/pipa_port/config.prop"
du -sh "$A"
set_layer "$STEP"
