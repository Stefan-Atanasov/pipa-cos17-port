#!/bin/bash
# Assemble a user release package from the beta4 release tree (same flash scripts and firmware) + our images.
#
#   bash maintainer/build_release.sh <tag> [--boot <boot.img>] [--name <version text>] [--no-super] [--7z]
#     <tag>        port-work/<tag>/img/super.img is the system (e.g. beta5-2g)
#     --boot       replace firmware/boot.img (our kernel); default: the beta4 kernel
#     --name       version text shown in the flash script banner (default: "beta5 (<tag>)")
#     --pkg        package name in the folder/7z name (default: <tag>), e.g. "beta5" for a public release
#     --no-super   skip the 6.8 GB super.img (to test the packaging)
#     --7z         also write <out>.7z next to the folder
# Output: ~/Documents/pipa/port-work/release/ColorOS17-Port-pipa-<tag>-<yyyymmdd>/
#
# Flash scripts (2026-11-20): our English templates in maintainer/release/ (menu: 1 = update, keep data; 2 = clean
# install, erase metadata + userdata + frp, confirmed with "ERASE"). The original port credit stays in the banner.
set -euo pipefail
COS=$(cd "$(dirname "$0")/.." && pwd)
SRC="$COS/ColorOS17 Port for pipa-beta4-20261017"
PW=${PIPA_ROOT:-$(cd "$COS/.." && pwd)}/port-work
MAINTAINER=${MAINTAINER:-stefan}

TAG=${1:?usage: build_release.sh <tag> [--pkg name] [--boot img] [--name text] [--no-super] [--7z]}; shift
BOOT=""; NAME="beta5 ($TAG)"; PKG=$TAG; SUPER=1; SEVENZ=0
while [ $# -gt 0 ]; do
	case "$1" in
	--boot) BOOT=$2; shift 2 ;;
	--name) NAME=$2; shift 2 ;;
	--pkg) PKG=$2; shift 2 ;;
	--no-super) SUPER=0; shift ;;
	--7z) SEVENZ=1; shift ;;
	*) echo "unknown option $1"; exit 1 ;;
	esac
done

SUPER_IMG=$PW/$TAG/img/super.img
[ -d "$SRC/firmware" ] || { echo "beta4 release tree missing (extract the beta4 .7z in COS17/; maintainer: HDD mounted?): $SRC"; exit 1; }
NOTES=$COS/RELEASE-NOTES-$PKG.md
[ -f "$NOTES" ] || { echo "missing $NOTES: write the notes or give --pkg <name> of existing notes"; exit 1; }
[ $SUPER = 0 ] || [ -f "$SUPER_IMG" ] || { echo "missing $SUPER_IMG"; exit 1; }
# never publish a maintainer build (step 5s: adb key + USB debugging on at the first boot)
if [ $SUPER = 0 ] || [ -f "$PW/$TAG/img/product.img" ]; then :; else echo "missing $PW/$TAG/img/product.img (needed for the 5s check)"; exit 1; fi
if [ $SUPER != 0 ] && dump.erofs --ls --path=/etc/security/adb_keys "$PW/$TAG/img/product.img" 2>/dev/null | grep -q "^Path"; then
    echo "REFUSED: $TAG is a maintainer build (product/etc/security/adb_keys, step 5s). Never publish it."; exit 1
fi
[ -z "$BOOT" ] || [ "$(head -c 8 "$BOOT")" = "ANDROID!" ] || { echo "not a boot image: $BOOT"; exit 1; }

OUT=$PW/release/ColorOS17-Port-pipa-$PKG-$(date +%Y%m%d)
rm -rf "$OUT"; mkdir -p "$OUT/super"
cp -a "$SRC/bin" "$SRC/firmware" "$OUT/"
chmod +x "$OUT"/bin/Linux/{adb,fastboot,magiskboot}
[ -z "$BOOT" ] || cp "$BOOT" "$OUT/firmware/boot.img"
[ $SUPER = 0 ] || cp --reflink=auto "$SUPER_IMG" "$OUT/super/super.img"

# Linux script (2026-11-20): our English template maintainer/release/FlashLinux.sh.in (menu: 1 = update, keep
# data; 2 = clean install, needs "ERASE"). Same partitions and order as the beta4 script (checked here), boot/dtbo
# only to slot B on an update (docs/DUALBOOT-LINUX.md), frp erased on a clean install.
python3 -I - "$COS/maintainer/release/FlashLinux.sh.in" "$OUT/FlashLinux.sh" "$NAME" "$MAINTAINER" "$SRC/FlashLinux.sh" <<'EOF2'
import re, sys
tpl, dst, name, maint, orig = sys.argv[1:]
s = open(tpl, encoding='utf-8').read().replace('@NAME@', name).replace('@MAINTAINER@', maint)
def parts(t):
    return [re.sub(r'(_ab|_b|\$BS|\$\{BS\}|"|%BS%)', '', p) for p in re.findall(r'^\s*(?:call :)?flash\s+(\S+)', t, re.M)]
a, b = parts(open(orig, encoding='utf-8').read()), parts(s)
assert a == b, 'flash list differs from beta4: %s vs %s' % (a, b)
open(dst, 'w', encoding='utf-8').write(s)
print('FlashLinux.sh: %d partitions as beta4' % len(b))
EOF2
chmod +x "$OUT/FlashLinux.sh"

# macOS script (2026-11-15, testers asked): the Linux script with Google's universal macOS fastboot (Intel + Apple
# Silicon, no extra libs) in bin/macOS. The script runs on macOS's bash 3.2. Gatekeeper: remove the download
# quarantine flag from the bundled fastboot. Fallback: fastboot in PATH (brew install android-platform-tools).
MAC_PT=$PW/release-tools/darwin/platform-tools
[ -x "$MAC_PT/fastboot" ] || { echo "missing $MAC_PT/fastboot: unzip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip into $PW/release-tools/darwin"; exit 1; }
mkdir -p "$OUT/bin/macOS"
cp "$MAC_PT/fastboot" "$MAC_PT/source.properties" "$MAC_PT/NOTICE.txt" "$OUT/bin/macOS/"
python3 -I - "$OUT/FlashLinux.sh" "$OUT/FlashMac.sh" <<'EOF'
import sys
src, dst = sys.argv[1:]
s = open(src, encoding='utf-8').read()
old = 'BIN_DIR="$SCRIPT_DIR/bin/Linux"\n'
assert s.count(old) == 1
s = s.replace(old, 'BIN_DIR="$SCRIPT_DIR/bin/macOS"\n')
old = 'chmod +x "$FASTBOOT" 2>/dev/null\n'
assert s.count(old) == 1
s = s.replace(old, old + 'xattr -d com.apple.quarantine "$FASTBOOT" 2>/dev/null\n', 1)
open(dst, 'w', encoding='utf-8').write(s)
EOF
chmod +x "$OUT/FlashMac.sh"

# Windows script (2026-11-20): our English template maintainer/release/FlashWindows.bat.in, UTF-8 (chcp 65001)
# with CRLF. Same partitions and order as the beta4 script (checked here).
python3 -I - "$COS/maintainer/release/FlashWindows.bat.in" "$OUT/FlashWindows.bat" "$NAME" "$MAINTAINER" "$SRC/FlashWindows.bat" <<'EOF2'
import re, sys
tpl, dst, name, maint, orig = sys.argv[1:]
s = open(tpl, encoding='utf-8').read().replace('@NAME@', name).replace('@MAINTAINER@', maint)
def parts(t):
    return [re.sub(r'(_ab|_b|%BS%|")', '', p) for p in re.findall(r'^\s*call :flash\s+(\S+)', t, re.M)]
a, b = parts(open(orig, 'rb').read().decode('gbk')), parts(s)
assert a == b, 'flash list differs from beta4: %s vs %s' % (a, b)
open(dst, 'wb').write(s.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'))
print('FlashWindows.bat: %d partitions as beta4' % len(b))
EOF2

# release notes: RELEASE-NOTES-<pkg>.md (e.g. beta6; checked at the start, no fallback to old notes)
cp "$NOTES" "$OUT/RELEASE-NOTES.md"
# extras: the SukiSU manager that matches the kernel (a clean flash removes the app) and the optional susfs module
mkdir -p "$OUT/extras"
KSU_APK=${KSU_APK:-$COS/kernel/sukisu-nova-3.0.0/SukiSU_Nova_v3.0.0_35000-arm64-v8a-release.apk}   # walt-hi9 and later (SukiSU Nova, step 7u); walt-r17..hi8: .../sukisu-v4.3.0-r1/SukiSU_v4.3.0-r1_41140-release.apk; walt-r8..r16: .../sukisu-v4.3.0/SukiSU_v4.3.0_41100-release.apk; walt-r6/r7: KSU_APK=.../sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk
for f in "$KSU_APK" "$COS/pipa-susfs-v1.0.zip"; do [ -f "$f" ] || { echo "missing extra: $f (KSU_APK= for another manager APK)"; exit 1; }; done
cp "$KSU_APK" "$OUT/extras/"
cp "$COS/pipa-susfs-v1.0.zip" "$OUT/extras/"
cat > "$OUT/README-FLASH.txt" <<EOF
ColorOS 17 port for Xiaomi Pad 6 (pipa) - $NAME
Original build: Coolapk @梦归zzz. Maintainer: $MAINTAINER.

Needs an unlocked bootloader. Back up your data first.
1. Reboot the tablet to the bootloader (power + volume down) and connect it to the PC.
2. Linux: ./FlashLinux.sh    Windows: FlashWindows.bat (Xiaomi/Google USB drivers installed)
   macOS: open Terminal, type "bash " (with a space), drag FlashMac.sh into the window, press Enter.
   Use a direct USB cable, not a hub (a hub can break the large super flash).
3. The script asks how to install: 1 = update (keeps apps and data, to update this port),
   2 = clean install (erases all data; first install or coming from another ROM; type ERASE to confirm).
4. The first boot takes a few minutes. Do not reboot it manually.
5. Root: the port installs the SukiSU manager on the first boot. If it is missing, install
   extras/$(basename "$KSU_APK") and open it once.
   Optional root hiding: extras/pipa-susfs-v1.0.zip as a module.
6. Start the flash script in a terminal: the install question needs an answer (1 or 2).
Rollback: flash the previous package the same way.
Play Integrity: BASIC only (unlocked bootloader). Known issues: see RELEASE-NOTES.md.
EOF

(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
du -sh "$OUT"
if [ $SEVENZ = 1 ]; then
	command -v 7z >/dev/null || { echo "7z not installed"; exit 1; }
	rm -f "$OUT.7z"   # 7z a would add to an old archive of the same name
	(cd "$(dirname "$OUT")" && 7z a -mx=5 "$(basename "$OUT").7z" "$(basename "$OUT")" >/dev/null)
	ls -la "$OUT.7z"
fi
echo "$OUT"
