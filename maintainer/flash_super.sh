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
P=${PIPA_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}   # the folder that holds COS17/
case ${1:?usage: flash_super.sh [-y] <name> (names: the case list below, e.g. beta6, beta4) or flash_super.sh [-y] <path> <md5>} in
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
    port-pt12)   IMG=$P/port-work/pt12/img/super.img;        MD5=7b3973dcde3e827ebba48079d71b9bc3 ;;   # pt11 + SukiSU manager v4.3.0 (41100) + upgrade logic, TEST
    port-pt13)   IMG=$P/port-work/pt13/img/super.img;        MD5=6b6a367b5d264e37950e32c309548304 ;;   # pt12 + 3p Google Photos NEXUS_PRELOAD feature, TEST
    port-pt14)   IMG=$P/port-work/pt14/img/super.img;        MD5=d0c2830e0c0d2b7ea79d02ef5eebada8 ;;   # pt13 + 3q HDR = Natural/P3 + EDR off, 3r Standard warm, pen capsule, Game Filter, nandswap sys_admin, TEST
    port-pt18)   IMG=$P/port-work/pt18/img/super.img;        MD5=496f03bc546fa09f0ef3b27e851b71c4 ;;   # pt14 + 3s adaptive tone (CCT stream, real lux, curves, bedtime, dark locks) + pipa_port loop ioctls, TEST
    beta6)       IMG=$P/port-work/beta6/img/super.img;       MD5=d79419f9cd8be13b9610ed95394da0e2 ;;   # pt18 content + 3t battery log + 3u pen dock + 3v fast service start + 3w face rules, RELEASE
    pt24)        IMG=$P/port-work/pt24/img/super.img;        MD5=2e0bb489e3b91e9055b257922d2012c5 ;;   # 4i-4l (screen attention, USB-C monitor, OShare, Quick Share), TEST
    pt26)        IMG=$P/port-work/pt26/img/super.img;        MD5=7242acc38c238f30b18767af7c59b044 ;;   # pt24 + 4m charge stop field, 4n QoS, 4o touch HAL, beta7-rc1
    pt27)        IMG=$P/port-work/pt27/img/super.img;        MD5=1494512b57d786ec4d368663fab28095 ;;   # pt26 + 4p bypass charging + service.sh process savings (cloud), TEST
    pt28)        IMG=$P/port-work/pt28/img/super.img;        MD5=473409600266101b73b83eb07c3cdbfb ;;   # pt27 content (+ usb/present fix) on donor C.07 (17.0.0.104), TEST
    pt29)        IMG=$P/port-work/pt29/img/super.img;        MD5=744c37c47733a9cf4cc553384d8b182e ;;   # pt28 + 4q VINTF removals + 4r HAL shim host (gameopt, panel, misc, touch), C.07, BOOTLOOP (two labels for gameopt), do not flash
    pt30)        IMG=$P/port-work/pt30/img/super.img;        MD5=675c329137a84db5b8ed58719dae33b6 ;;   # pt29 with the gameopt label fix (4r), C.07, TEST
    pt31)        IMG=$P/port-work/pt31/img/super.img;        MD5=7a3ba101b210fe469f0ef34b75a9f3ca ;;   # pt30 + charge cap (bypass, limit) + gameopt type 100 fix, C.07, TEST
    pt32)        IMG=$P/port-work/pt32/img/super.img;        MD5=db4cc06015ca68000589eb2e2b320c2b ;;   # pt31 + 4t Game Eye Care, C.07, TEST (beta7 candidate)
    pt33)        IMG=$P/port-work/pt33/img/super.img;        MD5=6051558be69b08890cb1216dc2dd776b ;;   # pt32 + 4u About banner (17.0) + 4v gesture bar 600 ms, C.07, TEST
    pt34)        IMG=$P/port-work/pt34/img/super.img;        MD5=ae8684ae3608440557c2001bfd179322 ;;   # pt33 + 4w bypass hysteresis (cap again at 20 %), C.07, TEST
    pt35)        IMG=$P/port-work/pt35/img/super.img;        MD5=1f69ceb319ebac5ab489c3722c4e060f ;;   # pt34 + 3o games as RedMagic Nova (BUGS 62), C.07, TEST
    pt36)        IMG=$P/port-work/pt36/img/super.img;        MD5=3fe1ecb2c5f9c28eca5d51d28013c2b0 ;;   # pt35 + 3o PUBG Nova + crDroid game devices (BUGS 62), C.07, TEST (beta7 candidate)
    pt37)        IMG=$P/port-work/pt37/img/super.img;        MD5=26fe62970cbe86701de1de880b4d6fe2 ;;   # pt36 + 4x no dedup scan / Turbo Pocket, C.07, TEST (beta7 candidate)
    pt39)        IMG=$P/port-work/pt39/img/super.img;        MD5=066d526c878d53079d2a2e7917bfce17 ;;   # pt38 + 4z boot image on /data (stale boot-framework removed), C.07, TEST
    pt40)        IMG=$P/port-work/pt40/img/super.img;        MD5=7449ec281f79fa3de6ec4dbd46d00892 ;;   # pt37 + 4y + 4z (no prebuilt boot image: odrefresh builds it on /data), C.07, TEST
    pt41)        IMG=$P/port-work/pt41/img/super.img;        MD5=59bc28c6a5c5db2ed09e3ccb62220504 ;;   # pt40 + 5a-5e (USB-C monitor 120 Hz, extended screen, float limit, PC Extend/Mirror odmf, monitor 200 dpi), C.07, TEST (beta7 candidate)
    pt42)        IMG=$P/port-work/pt42/img/super.img;        MD5=29bb1aa1b6ffb47be10611a4690bac1a ;;   # pt41 + 5f (SELinux rules from a full capture: UI First hints, f2fs GC nodes; Find My Device removed), C.07, TEST (beta7 candidate)
    pt43)        IMG=$P/port-work/pt43/img/super.img;        MD5=c6e79ee92e8deefe81cccc1f413dd470 ;;   # pt42 + 5f rules: ux_flag read, tcp sysctls, dontaudit vendor_init name props, C.07, TEST (beta7 candidate)
    pt44)        IMG=$P/port-work/pt44/img/super.img;        MD5=dab80f305af39e81ce7fa8f328728f56 ;;   # pt43 + 5g: launcher/SystemUI blur at tier 3 (app feature + debug.systemui.gaussblur_level=2), helper 0.9 two-state tile, TEST
    pt45)        IMG=$P/port-work/pt45/img/super.img;        MD5=c5e414ffe216431b18d6928d6c3cd030 ;;   # pt44 + 5h: SELinux clean-up (perf HAL ux_state, frame boost for more apps, dontaudit probes), TEST (beta7 candidate)
    pt46)        IMG=$P/port-work/pt46/img/super.img;        MD5=c1f54a2d0ab43b32624f5715815a1914 ;;   # pt45 + 5i: SELinux round 2 (UI First/frame boost hints, dontaudit probes) + Bedtime restore per key, TEST (beta7 candidate)
    pt47)        IMG=$P/port-work/pt47/img/super.img;        MD5=9bbfb1e5a850a868e18f277548f71011 ;;   # pt46 + 5j: SELinux round 3 (camera/media UX, dontaudit perf HAL scene writes, app probes), TEST (beta7 candidate)
    pt48)        IMG=$P/port-work/pt48/img/super.img;        MD5=5545aef33ca6b84a52bd379d9fe8404e ;;   # pt47 + 5k: last SELinux items (0 denials in normal + advanced capture), TEST (beta7 candidate)
    pt49)        IMG=$P/port-work/pt49/img/super.img;        MD5=c1dc3977c3853c5e4fca23e42b692595 ;;   # pt48 + 5l: Xiaomi game thermal profile while a game is in front (helper 1.0 GameKeeper, sconfig 20), TEST (beta7 candidate)
    pt50)        IMG=$P/port-work/pt50/img/super.img;        MD5=3075e8c9c4af377f929b42c545503b58 ;;   # pt49 + helper QUERY_ALL_PACKAGES (game detection works), beta7
    pt52)        IMG=$P/port-work/pt52/img/super.img;        MD5=c658bcb135eb57d866a9b7479905dbc9 ;;   # pt50 + 5m SukiSU manager r1 + 5n face worker guard, crashbox dontaudit (test; image deleted 2026-11-05)
    pt53)        IMG=$P/port-work/pt53/img/super.img;        MD5=baa21d5c0e6d80448c13f6a11cc7b85a ;;   # pt52 + 5o last SELinux noise (test; image deleted 2026-11-05)
    pt54)        IMG=$P/port-work/pt54/img/super.img;        MD5=2715d951f4a4a165153720fb6479308b ;;   # pt53 + 5p oiface/horae for SDK 34 games, gmscore frame boost (test)
    pt55)        IMG=$P/port-work/pt55/img/super.img;        MD5=95724aca3367900ab5c405e1136dfb5a ;;   # pt54 + 5q game service UI First ioctl = beta7 (release)
    *)           IMG=$1; MD5=${2:?md5 required for a custom path} ;;
esac
FB=fastboot

[ -f "$IMG" ] || { echo "image not found: $IMG"; echo "(most old build images are deleted; rebuild with maintainer/port/port.sh <tag> <donor-img-dir> [--until <step>], then: sh $0 -y <path> <md5>)"; exit 1; }
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
# Sometimes the bootloader answers every slot getvar with "not found" ('Device does not support slots'; seen
# 2026-11-02 and 2026-11-04). One `fastboot reboot bootloader` fixes it.
if ! $FB getvar current-slot 2>&1 | grep -q '^current-slot: '; then
    echo "bootloader does not report slots: rebooting the bootloader once"
    $FB reboot bootloader; sleep 3
    until $FB devices | grep -q fastboot; do sleep 1; done
    $FB getvar current-slot 2>&1 | grep -q '^current-slot: ' || { echo "still no slot info, stopping (nothing flashed)"; exit 1; }
fi
$FB set_active b
$FB flash super "$IMG"
$FB set_active b
$FB getvar current-slot 2>&1 | grep current-slot
$FB reboot
echo "flashed. First boot can take a few minutes. If it bootloops: sh $0 beta4"
