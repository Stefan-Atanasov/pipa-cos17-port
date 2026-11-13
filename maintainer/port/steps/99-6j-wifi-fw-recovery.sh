#!/bin/sh
# 6j (BUGS-TODO B1, other users 2026-10-22): "Wi-Fi sometimes does not turn on" has no recovery path.
#
# The QCA6390 driver (qcacld, in the kernel) reads vendor/etc/wifi/WCNSS_qcom_cfg.ini. The port ini (Lineage/PixelOS
# layout) has gEnableSelfRecovery=1 but not gEnableForceTargetAssert=1. Stock HyperOS has both ("#Enable SSR",
# vendor/etc/wifi/qca6390/WCNSS_qcom_cfg.ini line 23). Without it the driver cannot force a firmware assert when a
# command to the firmware times out, so self recovery does not start and Wi-Fi stays dead until a reboot.
# ColorOS's own recovery (sys.oplus.wifi.coldreset -> service wifi_cool_reset -> /sys/module/cnss2/parameters/
# pci_reset) cannot work on pipa: our cnss2 has no pci_reset parameter and the service has the seclabel su.
# * vendor/etc/wifi/WCNSS_qcom_cfg.ini: gEnableForceTargetAssert=1 after gEnableApOBSSProt=1 (as stock). The other
#   differences to stock (gIPAConfig, g11dSupportEnabled, gEnablefwlog, etsi13 SRD, concurrent STA) stay.
# * No layer change (no APK or jar changes).
# NOT TESTED when written (2026-11-11, offline; the failure was never reproduced on the maintainer tablet). Check on
# the tablet: Wi-Fi on/off 20 times, hotspot, `dmesg | grep -i -E "cnss|wlan"` shows no new error at driver load.
set -eu
. "$PORT/lib.sh"

F=vendor/etc/wifi/WCNSS_qcom_cfg.ini
echo "== 6j Wi-Fi firmware recovery (gEnableForceTargetAssert)"
[ -f "$T/$F" ] || die "no $T/$F"
forbid_grep "^gEnableForceTargetAssert" "$T/$F"
need_grep "^gEnableSelfRecovery=1" "$T/$F"
replace_once "$F" "gEnableApOBSSProt=1\n" "gEnableApOBSSProt=1\n\n#Enable SSR (pipa port 6j, as stock HyperOS)\ngEnableForceTargetAssert=1\n"
need_grep "^gEnableForceTargetAssert=1\$" "$T/$F"
