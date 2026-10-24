#!/bin/sh
# Flash one super.img to the tablet: super only, slot B, no firmware, no wipe.
#
#   sh flash_super.sh [-y] <name>     names below; or: sh flash_super.sh [-y] <path> <md5>
#   -y answers the confirmation prompt (needed when run without a terminal, e.g. via `!`)
#
# The tablet can be booted (ADB) or already in fastboot. The image md5 is checked first and the
# script stops on a mismatch. Rollback = the same script with "beta4".
set -eu
YES=0; [ "${1:-}" = -y ] && { YES=1; shift; }
P=~/Documents/pipa
case ${1:?usage: flash_super.sh roundtrip|beta4|beta5-2d|beta5-2e|beta5-2f|beta5-2g|beta5-2h|beta5-2i|beta5-2j|beta5-2k|beta5-2l|beta5-2m|beta5-2n|beta5-2o|beta5-2p|beta5-2q|beta5-2r|beta5-2s|beta5-2t  or  <path> <md5>} in
    roundtrip)   IMG=$P/port-work/roundtrip/img/super.img;   MD5=090e5a32031d61824c213284530daa01 ;;
    beta4)       IMG="$P/COS17/ColorOS17 Port for pipa-beta4-20261017/super/super.img"; MD5=4ba0e1937fe207be497eb42eac04ba48 ;;
    beta5-2d)    IMG=$P/port-work/beta5-2d/img/super.img;    MD5=3dfbe1816afec27f519ee0fed5b86145 ;;
    beta5-2e)    IMG=$P/port-work/beta5-2e/img/super.img;    MD5=3340aae245fcc14143d6bea544ed5150 ;;
    beta5-2f)    IMG=$P/port-work/beta5-2f/img/super.img;    MD5=bcf016f7d68fb51851f95e5885d68076 ;;
    beta5-2g)    IMG=$P/port-work/beta5-2g/img/super.img;    MD5=79add8ff20ff98d62981f3247901bbc0 ;;
    beta5-2h)    IMG=$P/port-work/beta5-2h/img/super.img;    MD5=82c48b0496d9e1f1f7619b2c84462295 ;;
    beta5-2i)    IMG=$P/port-work/beta5-2i/img/super.img;    MD5=d9c5bb8adf7644dc45726e9fb7bbc546 ;;
    beta5-2j)    IMG=$P/port-work/beta5-2j/img/super.img;    MD5=f5c63fabc1bc224d34494c42680fe9fb ;;
    beta5-2k)    IMG=$P/port-work/beta5-2k/img/super.img;    MD5=c4d337575af8daa4f18621ce6e01ada7 ;;
    beta5-2l)    IMG=$P/port-work/beta5-2l/img/super.img;    MD5=b517e27b3445b9449f4d0fbb1d12449f ;;
    beta5-2m)    IMG=$P/port-work/beta5-2m/img/super.img;    MD5=989d94be82b18fb8db5aa41e6632f9f6 ;;
    beta5-2n)    IMG=$P/port-work/beta5-2n/img/super.img;    MD5=ece2e9e11c2506b86efde8e6fb28d8df ;;
    beta5-2o)    IMG=$P/port-work/beta5-2o/img/super.img;    MD5=8b0133e3426f45b707b31c98f1d6f29c ;;
    beta5-2p)    IMG=$P/port-work/beta5-2p/img/super.img;    MD5=8041c1563a559b88ec0e2cdd3d702996 ;;
    beta5-2q)    IMG=$P/port-work/beta5-2q/img/super.img;    MD5=9de195f15f9c28822f83dd23eaa88d54 ;;
    beta5-2r)    IMG=$P/port-work/beta5-2r/img/super.img;    MD5=6b102f06d38a50c8a90ae75555766a4b ;;
    beta5-2s)    IMG=$P/port-work/beta5-2s/img/super.img;    MD5=cf4e642ff938c97fb695f9b92b93af11 ;;
    beta5-2t)    IMG=$P/port-work/beta5-2t/img/super.img;    MD5=cfc39157a4e689da5ce62e9da0814642 ;;
    *)           IMG=$1; MD5=${2:?md5 required for a custom path} ;;
esac
FB=fastboot

[ -f "$IMG" ] || { echo "image not found: $IMG"; echo "(older build images were deleted on 2026-10-23 to save space; rebuild with maintainer/build_port.sh)"; exit 1; }
echo "image: $IMG"
echo "checking md5 (takes ~30 s)..."
got=$(md5sum "$IMG" | cut -d' ' -f1)
[ "$got" = "$MD5" ] || { echo "md5 mismatch: $got != $MD5, not flashing"; exit 1; }
echo "md5 ok"

if adb devices | grep -qw device; then
    echo "rebooting to bootloader..."
    adb reboot bootloader
fi
echo "waiting for fastboot..."
until $FB devices | grep -q fastboot; do sleep 1; done
$FB getvar product 2>&1 | grep -q pipa || { echo "fastboot device is not pipa, stopping"; exit 1; }

if [ $YES = 1 ]; then ok=y; else printf 'Flash super (slot B, no wipe)? [y/N] '; read -r ok || ok=; fi
[ "$ok" = y ] || { echo "aborted, nothing flashed (tablet stays in fastboot: 'fastboot reboot' to boot)"; exit 1; }
$FB set_active b
$FB flash super "$IMG"
$FB set_active b
$FB getvar current-slot 2>&1 | grep current-slot
$FB reboot
echo "flashed. First boot can take a few minutes. If it bootloops: sh $0 beta4"
