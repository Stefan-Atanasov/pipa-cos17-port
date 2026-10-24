#!/bin/bash
# Assemble a user release package from the beta4 release tree (same flash scripts and firmware) + our images.
#
#   bash maintainer/build_release.sh <tag> [--boot <boot.img>] [--name <version text>] [--no-super] [--7z]
#     <tag>        port-work/<tag>/img/super.img is the system (e.g. beta5-2g)
#     --boot       replace firmware/boot.img (our kernel); default: the beta4 kernel
#     --name       version text shown in the flash script banner (default: "beta5 (<tag>)")
#     --no-super   skip the 6.8 GB super.img (to test the packaging)
#     --7z         also write <out>.7z next to the folder
# Output: ~/Documents/pipa/port-work/release/ColorOS17-Port-pipa-<tag>-<yyyymmdd>/
#
# The flash scripts keep the original behaviour: one script, "y" = clean flash (erase metadata + userdata),
# Enter = dirty flash (keep data). The original build credit stays; a maintainer line is added.
set -euo pipefail
COS=$HOME/Documents/pipa/COS17
SRC="$COS/ColorOS17 Port for pipa-beta4-20261017"
PW=$HOME/Documents/pipa/port-work
MAINTAINER=${MAINTAINER:-stefan}

TAG=${1:?usage: build_release.sh <tag> [--boot img] [--name text] [--no-super] [--7z]}; shift
BOOT=""; NAME="beta5 ($TAG)"; SUPER=1; SEVENZ=0
while [ $# -gt 0 ]; do
	case "$1" in
	--boot) BOOT=$2; shift 2 ;;
	--name) NAME=$2; shift 2 ;;
	--no-super) SUPER=0; shift ;;
	--7z) SEVENZ=1; shift ;;
	*) echo "unknown option $1"; exit 1 ;;
	esac
done

SUPER_IMG=$PW/$TAG/img/super.img
[ -d "$SRC/firmware" ] || { echo "beta4 release tree missing (HDD mounted?): $SRC"; exit 1; }
[ $SUPER = 0 ] || [ -f "$SUPER_IMG" ] || { echo "missing $SUPER_IMG"; exit 1; }
[ -z "$BOOT" ] || [ "$(head -c 8 "$BOOT")" = "ANDROID!" ] || { echo "not a boot image: $BOOT"; exit 1; }

OUT=$PW/release/ColorOS17-Port-pipa-$TAG-$(date +%Y%m%d)
rm -rf "$OUT"; mkdir -p "$OUT/super"
cp -a "$SRC/bin" "$SRC/firmware" "$OUT/"
chmod +x "$OUT"/bin/Linux/{adb,fastboot,magiskboot}
[ -z "$BOOT" ] || cp "$BOOT" "$OUT/firmware/boot.img"
[ $SUPER = 0 ] || cp --reflink=auto "$SUPER_IMG" "$OUT/super/super.img"

# Linux script: banner + make the bundled fastboot executable (7z/zip lose the exec bit), else use the system one
python3 -I - "$SRC/FlashLinux.sh" "$OUT/FlashLinux.sh" "$NAME" "$MAINTAINER" <<'EOF'
import sys
src, dst, name, maint = sys.argv[1:]
s = open(src, encoding='utf-8').read()
old = 'echo "System version: ColorOS17 / Android 17"\n'
assert s.count(old) == 1
s = s.replace(old, old.replace('Android 17"', f'Android 17 {name}"') +
              f'echo\necho "维护者：{maint}"\necho "Maintainer: {maint}"\n')
old = '[[ -x "$FASTBOOT" ]] ||'
assert s.count(old) == 1
s = s.replace(old, 'chmod +x "$FASTBOOT" 2>/dev/null\n'
              '[[ -x "$FASTBOOT" ]] || FASTBOOT="$(command -v fastboot || true)"\n'
              '[[ -n "$FASTBOOT" && -x "$FASTBOOT" ]] ||', 1)
open(dst, 'w', encoding='utf-8').write(s)
EOF
chmod +x "$OUT/FlashLinux.sh"

# Windows script: GBK + CRLF like the original (cmd runs it with chcp 936)
python3 -I - "$SRC/FlashWindows.bat" "$OUT/FlashWindows.bat" "$NAME" "$MAINTAINER" <<'EOF'
import sys
src, dst, name, maint = sys.argv[1:]
s = open(src, 'rb').read().decode('gbk')
old = 'echo System version: ColorOS 17 / Android 17\r\n'
assert s.count(old) == 1
s = s.replace(old, old.replace('Android 17', f'Android 17 {name}') +
              f'echo.\r\necho 维护者：{maint}\r\necho Maintainer: {maint}\r\n')
open(dst, 'wb').write(s.encode('gbk'))
EOF

[ -f "$COS/RELEASE-NOTES-beta5.md" ] && cp "$COS/RELEASE-NOTES-beta5.md" "$OUT/RELEASE-NOTES.md"
cat > "$OUT/README-FLASH.txt" <<EOF
ColorOS 17 port for Xiaomi Pad 6 (pipa) - $NAME
Original build: Coolapk @梦归zzz. Maintainer: $MAINTAINER.

Needs an unlocked bootloader. Back up your data first.
1. Reboot the tablet to the bootloader (power + volume down) and connect it to the PC.
2. Linux: ./FlashLinux.sh    Windows: FlashWindows.bat (Xiaomi/Google USB drivers installed)
3. The script asks: "y" = clean flash (erases all data, needed when coming from another ROM),
   Enter = dirty flash (keeps data, for updating this port).
4. The first boot takes a few minutes. Do not reboot it manually.
Rollback: flash the previous package the same way.
Play Integrity: BASIC only (unlocked bootloader). Known issues: see RELEASE-NOTES.md.
EOF

(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
du -sh "$OUT"
if [ $SEVENZ = 1 ]; then
	command -v 7z >/dev/null || { echo "7z not installed"; exit 1; }
	(cd "$(dirname "$OUT")" && 7z a -mx=5 "$(basename "$OUT").7z" "$(basename "$OUT")" >/dev/null)
	ls -la "$OUT.7z"
fi
echo "$OUT"
