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
case ${1:?usage: flash_super.sh roundtrip|beta4|beta5-2d|beta5-2e|beta5-2f|beta5-2g|beta5-2h|beta5-2i|beta5-2j|beta5-2k|beta5-2l|beta5-2m|beta5-2n|beta5-2o|beta5-2p|beta5-2q|beta5-2r|beta5-2s|beta5-2t|beta5-2u|beta5-2v|beta5-2w|beta5-2x|beta5-2y  or  <path> <md5>} in
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
    beta5-2u)    IMG=$P/port-work/beta5-2u/img/super.img;    MD5=e50a67c459da943d9c570d4f0a618706 ;;
    beta5-2v)    IMG=$P/port-work/beta5-2v/img/super.img;    MD5=4bd035e9d3ee1ad742796bf6420fda7b ;;
    beta5-2w)    IMG=$P/port-work/beta5-2w/img/super.img;    MD5=220a449b753e8051f2aa1abeea78a501 ;;
    beta5-2x)    IMG=$P/port-work/beta5-2x/img/super.img;    MD5=c0eaec48e68bc3c8bfc7d67138aacfb3 ;;
    beta5-2y)    IMG=$P/port-work/beta5-2y/img/super.img;    MD5=d14341692447a5934cd1ef7b432a13a7 ;;
    beta5-2z)    IMG=$P/port-work/beta5-2z/img/super.img;    MD5=10a96a0384ecd8945ff083305723fba3 ;;
    beta5-3a)    IMG=$P/port-work/beta5-3a/img/super.img;    MD5=fe3a01420b4e1c30a5372981c67b263d ;;
    beta5-3b)    IMG=$P/port-work/beta5-3b/img/super.img;    MD5=f85d4d5b1208c14719a0c70dbaea83e6 ;;
    beta5-3c)    IMG=$P/port-work/beta5-3c/img/super.img;    MD5=2a253f6501de7cef2be9c76ca7770654 ;;
    beta5-3d)    IMG=$P/port-work/beta5-3d/img/super.img;    MD5=2831f53923a046c428507b5f60b6102b ;;
    beta5-3e)    IMG=$P/port-work/beta5-3e/img/super.img;    MD5=2efdaae3aaf4480520e1eddfffafa479 ;;
    beta5-3f)    IMG=$P/port-work/beta5-3f/img/super.img;    MD5=88262647f430cef1a37a3f179e1d9826 ;;
    beta5-3g)    IMG=$P/port-work/beta5-3g/img/super.img;    MD5=3fe7303c70ea87d39a091b29204a7567 ;;
    beta5-3h)    IMG=$P/port-work/beta5-3h/img/super.img;    MD5=6842099375e52a27dfd135365f361df6 ;;
    beta5-3i)    IMG=$P/port-work/beta5-3i/img/super.img;    MD5=16cd33c2d9d17875141e13c9a925dbcc ;;
    beta5-3j)    IMG=$P/port-work/beta5-3j/img/super.img;    MD5=98820de3af5df2349d311505ba6e9c39 ;;
    port-pt3)    IMG=$P/port-work/pt3/img/super.img;         MD5=cd30ab3df125f3849e435de4b09a9e44 ;;   # port.sh (single tree) = 3j
    port-pt4)    IMG=$P/port-work/pt4/img/super.img;         MD5=b75a944c851144b14073f4085f35cb5e ;;   # pt3 + 3k (odm interconnect from C.06), TEST
    port-pt6)    IMG=$P/port-work/pt6/img/super.img;         MD5=3b76c9b6e9c78a98fb3148a2c561038c ;;   # pt3 + 3l (64-bit mediaserver), TEST
    port-pt7)    IMG=$P/port-work/pt7/img/super.img;         MD5=feeab1558be8de8a2fe8392bab2043fd ;;   # pt6 + 3m (media profiles path), TEST
    port-pt8)    IMG=$P/port-work/pt8/img/super.img;         MD5=b0b557e6ce56b11b439e73e696b7cd97 ;;   # pt7 + 3n (pen ready ~1 s after screen-on), TEST
    port-pt9)    IMG=$P/port-work/pt9/img/super.img;         MD5=99daa786ff18801e4b3a48b2d3b69f01 ;;   # pt8 + pipa_port map on apex_art_data_file (boot.oat), TEST
    port-pt10)   IMG=$P/port-work/pt10/img/super.img;        MD5=15281b87ea5d88c2452e291c6515d711 ;;   # pt9 + 3o per-app identity (Netflix Pixel 6, Google Photos Pixel XL), TEST
    port-pt11)   IMG=$P/port-work/pt11/img/super.img;        MD5=073694b0db32209dc040849d5f6ceb28 ;;   # pt10 + pipa_port boot.oat execute + statsdw dontaudit (3o side effect), TEST
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
