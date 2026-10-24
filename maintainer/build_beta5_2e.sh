#!/bin/sh
# Phase 2e: the pipa_port module moves into the ROM, on top of beta5-2d. Build the helper first
# (sh ../helper/build.sh), then run as root:
#
#   sudo sh build_beta5_2e.sh
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
# Input: port-work/${TAG}-2d/tree/{system,system_ext}, port-work/${TAG}-2d/img. Output: port-work/${TAG}-2e/.
set -eu
TAG=${TAG:-beta5}   # base name: work dirs are port-work/$TAG, $TAG-baked, $TAG-2f, ... (build_port.sh sets it)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2d/img
W=$P/${TAG}-2e
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
APK=$HERE/../helper/out/PipaHelper.apk
BOOTANIM=$HERE/bootanim
OWNER=${PIPA_OWNER:-stefan:stefan}
PKG=com.port.pipa.helper
LABEL=u:object_r:system_file:s0
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2d.sh first"; exit 1; }
[ -f "$APK" ] || { echo "build the helper first: sh helper/build.sh"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2d/tree/system" "$P/${TAG}-2d/tree/system_ext" "$W/tree/"
S=$W/tree/system/system
SE=$W/tree/system_ext
MP=$W/tree/system/my_product

replace_once() {   # replace_once <file> <old> <new>: exactly one match, same inode (label kept)
    python3 -I - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]
old, new = old.encode().decode('unicode_escape'), new.encode().decode('unicode_escape')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != 1:
    sys.exit(f"{p}: anchor found {n} times, expected 1")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:
    f.write(s.replace(old, new)); f.truncate()
PY
    echo "edited  ${1#$W/tree/}"
}
replace_all() {    # replace_all <file> <old> <new> <count>
    python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
p, old, new, cnt = sys.argv[1:]
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != int(cnt):
    sys.exit(f"{p}: anchor found {n} times, expected {cnt}")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:
    f.write(s.replace(old, new)); f.truncate()
PY
    echo "edited  ${1#$W/tree/} ($4x)"
}
label() { setfattr -n security.selinux -v "$LABEL" "$@"; }

echo "== pipa_port runtime -> /system_ext/pipa_port"
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
cp "$APK" "$W/report/PipaHelper.apk"
T=$(mktemp -d)
cat > "$T/privapp.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- pipa port: LidKeeper mirrors the "lock with cover" switch into global lid_behavior (B14) -->
<permissions>
    <privapp-permissions package="$PKG">
        <permission name="android.permission.WRITE_SECURE_SETTINGS" />
    </privapp-permissions>
</permissions>
EOF
install -o 0 -g 0 -m 644 "$T/privapp.xml" "$S/etc/permissions/privapp-permissions-pipa-helper.xml"
label "$S/etc/permissions/privapp-permissions-pipa-helper.xml"
rm -rf "$T"
echo "added   system/priv-app/PipaHelper, etc/permissions/privapp-permissions-pipa-helper.xml"

echo "== label check"
for p in system system_ext; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$p" > "$W/report/$p.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$p.tsv" | wc -l)
    echo "$p: $(wc -l < "$W/report/$p.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system system_ext)"
for p in system system_ext; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$p.img" "$W/tree/$p" > "$W/report/mkfs_$p.log" 2>&1
done
for p in product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
