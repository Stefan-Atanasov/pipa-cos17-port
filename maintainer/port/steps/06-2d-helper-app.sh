#!/bin/sh
# Phase 2d: the pipa helper app as a persistent system app, on top of beta5-2c (BUGS-TODO.md B10, B3).
# Build the app before the run: sh ../helper/build.sh
#
# B10 Dolby at boot: helper DolbyKeeper holds Xiaomi's DAP effect on the global output mix and
#    re-applies the saved state (HyperOS does this in system_server, the port had no holder). It
#    calls AudioEffect's hidden setParameter/getParameter, so the package is listed in a sysconfig
#    hidden-api whitelist (same mechanism as MiSound's), which only applies to system apps.
# B3 pen battery: helper PenKeeper shows the pill on dock/undock and a low-battery notification,
#    from global pipa_pen_state (published by power-tune v0.15+).
# persistent="true" is honoured only for system apps: ActivityManager starts it at boot and
#    ColorOS's background cleaner leaves it alone (a user-app copy was killed after ~20 s).
# POST_NOTIFICATIONS is listed in default-permissions, but Android applies those only on a first
#    boot / fingerprint change; power-tune v0.15 also grants it and the overlay appop as root.
#
# Old layer script: build_beta5_2d.sh
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
APK=$HERE/../helper/out/PipaHelper.apk
PKG=com.port.pipa.helper
[ -f "$APK" ] || die "build the helper first: sh helper/build.sh"

S=$T/system/system
LABEL=u:object_r:system_file:s0

add_file() {   # add_file <src> <dest under system/system> : root:root 644, system_file label
    mkdir -p "$(dirname "$S/$2")"
    install -o 0 -g 0 -m 644 "$1" "$S/$2"
    setfattr -n security.selinux -v "$LABEL" "$S/$2"
    echo "added   system/$2"
}

echo "== pipa helper $(md5sum < "$APK" | cut -c1-32)"
cp "$APK" "$R/PipaHelper.apk"
mkdir -p "$S/app/PipaHelper"
chmod 755 "$S/app/PipaHelper"
setfattr -n security.selinux -v "$LABEL" "$S/app/PipaHelper"
add_file "$APK" app/PipaHelper/PipaHelper.apk

TMPD=$(mktemp -d)
cat > "$TMPD/hiddenapi.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: DolbyKeeper uses AudioEffect.setParameter/getParameter(int, byte[]) (B10) -->
<config>
    <hidden-api-whitelisted-app package="$PKG" />
</config>
EOF
cat > "$TMPD/default-perms.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: pen battery notifications (B3) -->
<exceptions>
    <exception package="$PKG">
        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false" />
    </exception>
</exceptions>
EOF
add_file "$TMPD/hiddenapi.xml" etc/sysconfig/pipa-helper-hiddenapi-package-whitelist.xml
add_file "$TMPD/default-perms.xml" etc/default-permissions/pipa-helper-permissions.xml
rm -rf "$TMPD"

