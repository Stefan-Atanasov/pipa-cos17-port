#!/bin/sh
# Phase 2e: the pipa_port module moves into the ROM, on top of beta5-2d. Build the helper before
# the run (sh ../helper/build.sh).
#
# * /system_ext/pipa_port (port-rom/pipa_port: face HAL + crop add-on, charger shim, pen tools,
#   service.sh = module v1.3 with ROM paths, early.sh) started by /system_ext/etc/init/pipa_port.rc
#   in the new domain pipa_port. The domain is PERMISSIVE in 2e only: boot it once, collect the
#   AVCs with maintainer/avc_trace.sh, and 2f adds the rules and drops typepermissive.
# * B13: my_product/build.prop ro.panel.pad_orientation 0 -> 90 (first WM rotation landscape);
#   my_product/media/bootanimation/{,r}bootanimation.zip with the logo centred (offsety 0).
# * traced off by build.prop (the kernel has no vsock; it crash-looped every 5 s).
# * pipa helper 0.4 (LidKeeper, B14) moves to /system/priv-app with WRITE_SECURE_SETTINGS.
# * susfs root hiding is NOT in the ROM (root-only extra): pipa_susfs module.
#
# Old layer script: build_beta5_2e.sh
#NEEDS: "$HERE/../helper/out/PipaHelper.apk" "$ROM/pipa_port" "$ROM/pipa_port.rc" "$HERE/bootanim/bootanimation.zip" "$HERE/bootanim/rbootanimation.zip" "$ROM/pipa_port/facehal/lib64/libpipa_facecrop.so"
set -eu
. "$PORT/lib.sh"
APK=$HERE/../helper/out/PipaHelper.apk
BOOTANIM=$HERE/bootanim
PKG=com.port.pipa.helper
LABEL=u:object_r:system_file:s0
[ -f "$APK" ] || die "build the helper first: sh helper/build.sh"

S=$T/system/system
SE=$T/system_ext
MP=$T/system/my_product

label() { setfattr -n security.selinux -v "$LABEL" "$@"; }

echo "== pipa_port runtime -> /system_ext/pipa_port"
[ ! -e "$SE/pipa_port" ] || die "system_ext/pipa_port exists in the donor: cp -a would nest into it"
cp -a "$ROM/pipa_port" "$SE/pipa_port"
chown -R 0:0 "$SE/pipa_port"
find "$SE/pipa_port" -type d -exec chmod 755 {} +
find "$SE/pipa_port" -type f -exec chmod 644 {} +
chmod 755 "$SE/pipa_port/xiaomi_touch_ioctl" "$SE/pipa_port/facehal/android.hardware.biometrics.face-service.facehal"
find "$SE/pipa_port" -exec setfattr -n security.selinux -v "$LABEL" {} +
install -o 0 -g 0 -m 644 "$ROM/pipa_port.rc" "$SE/etc/init/pipa_port.rc"
label "$SE/etc/init/pipa_port.rc"
echo "added   system_ext/pipa_port ($(find "$SE/pipa_port" -type f | wc -l) files), etc/init/pipa_port.rc"

echo "== SELinux: pipa_port domain (permissive in 2e)"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    python3 -I - "$SE/$f" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8', errors='surrogateescape').read()
m = re.search(r'^\(typeattributeset domain \((.*)\)\)$', s, re.M)
if not m or ' pipa_port ' in m.group(1) + ' ':
    sys.exit(f"{p}: domain set not found or already patched")
s = s[:m.end(1)] + 'pipa_port ' + s[m.end(1):]
block = """
;; ================= pipa port 2e: runtime services (system_ext/etc/init/pipa_port.rc) =========
;; Permissive for one test build; 2f replaces typepermissive with the rules from avc_trace.sh.
(type pipa_port)
(roletype object_r pipa_port)
(typepermissive pipa_port)
(allow init pipa_port (process (transition siginh rlimitinh noatsecure sigkill signal)))
(allow init shell_exec (file (read getattr map execute open)))
(allow init hal_radio_default_exec (file (read getattr map execute open)))
;; enforcing peers of the services (face HAL, charger shim, virtual modem HALs)
(allow domain pipa_port (binder (call transfer)))
(allow domain pipa_port (fd (use)))
(allow servicemanager pipa_port (dir (search)))
(allow servicemanager pipa_port (file (read open)))
(allow servicemanager pipa_port (process (getattr)))
(allow hwservicemanager pipa_port (dir (search)))
(allow hwservicemanager pipa_port (file (read open)))
(allow hwservicemanager pipa_port (process (getattr)))
"""
open(p, 'r+', encoding='utf-8', errors='surrogateescape').write(s.rstrip('\n') + '\n' + block)
PY
    echo "edited  system_ext/$f"
done

echo "== B13 boot rotation + logo"
replace_all "$MP/build.prop" 'ro.panel.pad_orientation=0' 'ro.panel.pad_orientation=90' 2
for z in bootanimation.zip rbootanimation.zip; do
    install -o 0 -g 0 -m 644 "$BOOTANIM/$z" "$MP/media/bootanimation/$z"
    label "$MP/media/bootanimation/$z"
    echo "replaced my_product/media/bootanimation/$z ($(md5sum < "$BOOTANIM/$z" | cut -c1-8))"
done

echo "== traced off"
printf '\n# pipa port: traced aborts without vsock (kernel lacks CONFIG_VSOCKETS) and init restarted it every 5 s\npersist.traced.enable=0\npersist.device_config.global_settings.sys_traced=0\n' >> "$S/build.prop"
echo "edited  system/build.prop"

echo "== pipa helper $(md5sum < "$APK" | cut -c1-32) -> priv-app"
rm -rf "$S/app/PipaHelper"
mkdir -p "$S/priv-app/PipaHelper"; chmod 755 "$S/priv-app/PipaHelper"; label "$S/priv-app/PipaHelper"
install -o 0 -g 0 -m 644 "$APK" "$S/priv-app/PipaHelper/PipaHelper.apk"; label "$S/priv-app/PipaHelper/PipaHelper.apk"
cp "$APK" "$R/PipaHelper.apk"
TMPD=$(mktemp -d)
cat > "$TMPD/privapp.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: LidKeeper mirrors the "lock with cover" switch into global lid_behavior (B14) -->
<permissions>
    <privapp-permissions package="$PKG">
        <permission name="android.permission.WRITE_SECURE_SETTINGS" />
    </privapp-permissions>
</permissions>
EOF
install -o 0 -g 0 -m 644 "$TMPD/privapp.xml" "$S/etc/permissions/privapp-permissions-pipa-helper.xml"
label "$S/etc/permissions/privapp-permissions-pipa-helper.xml"
rm -rf "$TMPD"
echo "added   system/priv-app/PipaHelper, etc/permissions/privapp-permissions-pipa-helper.xml"

