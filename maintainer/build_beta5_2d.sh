#!/bin/sh
# Phase 2d: the pipa helper app as a persistent system app, on top of beta5-2c (BUGS-TODO.md B10, B3).
# Build the app first (sh ../helper/build.sh), then run as root:
#
#   sudo sh build_beta5_2d.sh
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
# Input: port-work/${TAG}-2c/tree/{system,system_ext}, port-work/${TAG}-2c/img, helper/out/PipaHelper.apk.
# Output: port-work/${TAG}-2d/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2c/img
W=$P/${TAG}-2d
HERE=$(cd "$(dirname "$0")" && pwd)
APK=$HERE/../helper/out/PipaHelper.apk
OWNER=${PIPA_OWNER:-stefan:stefan}
PKG=com.port.pipa.helper
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2c.sh first"; exit 1; }
[ -f "$APK" ] || { echo "build the helper first: sh helper/build.sh"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2c/tree/system" "$P/${TAG}-2c/tree/system_ext" "$W/tree/"
S=$W/tree/system/system
LABEL=u:object_r:system_file:s0

add_file() {   # add_file <src> <dest under system/system> : root:root 644, system_file label
    mkdir -p "$(dirname "$S/$2")"
    install -o 0 -g 0 -m 644 "$1" "$S/$2"
    setfattr -n security.selinux -v "$LABEL" "$S/$2"
    echo "added   system/$2"
}

echo "== pipa helper $(md5sum < "$APK" | cut -c1-32)"
cp "$APK" "$W/report/PipaHelper.apk"
mkdir -p "$S/app/PipaHelper"
chmod 755 "$S/app/PipaHelper"
setfattr -n security.selinux -v "$LABEL" "$S/app/PipaHelper"
add_file "$APK" app/PipaHelper/PipaHelper.apk

T=$(mktemp -d)
cat > "$T/hiddenapi.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: DolbyKeeper uses AudioEffect.setParameter/getParameter(int, byte[]) (B10) -->
<config>
    <hidden-api-whitelisted-app package="$PKG" />
</config>
EOF
cat > "$T/default-perms.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: pen battery notifications (B3) -->
<exceptions>
    <exception package="$PKG">
        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false" />
    </exception>
</exceptions>
EOF
add_file "$T/hiddenapi.xml" etc/sysconfig/pipa-helper-hiddenapi-package-whitelist.xml
add_file "$T/default-perms.xml" etc/default-permissions/pipa-helper-permissions.xml
rm -rf "$T"

echo "== label check"
for p in system system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$p" > "$W/report/$p.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | wc -l)
    echo "$p: $(wc -l < "$W/report/$p.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system.img" "$W/tree/system" > "$W/report/mkfs_system.log" 2>&1
for p in system_ext product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
ls -l "$W/img"

echo "== super"
cd "$W/img"
set --
for p in system system_ext product vendor odm; do set -- "$@" --partition "${p}_a:readonly:0:qti_dynamic_partitions_a"; done
for p in system system_ext product vendor odm; do
    set -- "$@" --partition "${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b" --image "${p}_b=$p.img"
done
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab \
    --device super:9126805504 \
    --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
    "$@" --sparse --output super.img 2>&1 | grep -v -e 'will resize' -e 'Invalid sparse' || true
ls -l super.img
md5sum super.img
chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
