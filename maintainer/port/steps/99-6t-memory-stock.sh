#!/bin/sh
# Step 6t (BUGS-TODO 89/99, user 2026-11-14 "RAM like stock OPPO, best performance and efficiency"): memory setup as
# on stock OPPO tablets (port-work/codex/ram-stock/REPORT.md; baseline port-work/mem-checks/*-pt93*).
# 1. The beta4 porter's odm/etc/init.oplus.mm-sys.sh replaced OPPO's own setup: zram 8192 MB lz4 + a loop swap file
#    on f2fs for "RAM expansion" (reclaim can wait on f2fs = game stall path). Removed: OPPO's
#    product/bin/init.oplus.nandswap.sh main() runs again (its boot_completed branch only calls the odm script if it
#    exists): SM8250 > 6 GB = zram 5632 MB zstd + vm/direct swappiness 200/60 (via /proc/oplus_healthinfo/
#    swappiness_para, kernel walt-r23+), 6 GB = 3072 MB lz4 / 160. Without OPPO's hybridswap/nandswap kernel,
#    OPPO's nandswap_init frees its loop device and sets err 1004: no flash swap (stock behaviour on such a kernel).
# 2. The Qualcomm vendor init.qcom.post_boot.sh raced OPPO's scripts at boot_completed (both start at ~31 s): it wrote
#    swappiness 60 + watermark_scale_factor 1 and set up zram 4096 MB when it got there first (baseline pt93: wsf 1,
#    swappiness 60; after another boot wsf 25). On stock OPPO the memory values belong to OPPO's scripts
#    (system_ext init.sys.oplus.mm.post_boot.sh: wsf 25, boost 0). Removed those three writes; the rest stays.
# 3. OPPO lmkd thresholds as on stock OPPO tablets (OnePlus Pad 2 Pro / Pad 3 odm/build.prop): 700/1000/1200 MB.
set -eu
. "$PORT/lib.sh"
STEP=6t
Q=$T/vendor/bin/init.qcom.post_boot.sh
M=$T/odm/etc/init.oplus.mm-sys.sh
OP=$T/odm/etc/build.prop
[ -f "$Q" ] || die "$Q not found"
[ -f "$OP" ] || die "$OP not found"
need_grep 'if \[ -f "/odm/etc/init.oplus.mm-sys.sh" \]' "$T/product/bin/init.oplus.nandswap.sh"

echo "== 6t remove the porter's odm mm-sys.sh (OPPO main() runs)"
[ -f "$M" ] || die "$M not found"
rm -f "$M"

echo "== 6t vendor init.qcom.post_boot.sh: leave swappiness, wsf and zram to OPPO's scripts"
replace_once "$Q" '    echo 0 > /sys/module/vmpressure/parameters/allocstall_threshold
    echo 60 > /proc/sys/vm/swappiness

    # Disable wsf for all targets beacause we are using efk.
    # wsf Range : 1..1000 So set to bare minimum value 1.
    echo 1 > /proc/sys/vm/watermark_scale_factor
' '    echo 0 > /sys/module/vmpressure/parameters/allocstall_threshold
    # pipa 6t: swappiness and watermark_scale_factor are set by OPPO (init.oplus.nandswap.sh, init.sys.oplus.mm.post_boot.sh)
'
replace_once "$Q" '    configure_zram_parameters

    configure_read_ahead_kb_values' '    # pipa 6t: zram is set up by OPPO init.oplus.nandswap.sh
    configure_read_ahead_kb_values'
forbid_grep '^    echo 60 > /proc/sys/vm/swappiness$' "$Q"

echo "== 6t odm build.prop: OPPO lmkd thresholds"
forbid_grep 'lmkd_super_critical_threshold' "$OP"
{ cat "$OP"; printf '\n# pipa 6t: OPPO lmkd thresholds (stock OPPO tablets)\npersist.sys.oplus.lmkd_super_critical_threshold_8g=700\npersist.sys.oplus.lmkd_super_critical_threshold_12g=1000\npersist.sys.oplus.lmkd_super_critical_threshold_16g=1200\n'; } > "$R/odm.prop.new"
cat "$R/odm.prop.new" > "$OP"
need_grep '^persist.sys.oplus.lmkd_super_critical_threshold_8g=700$' "$OP"

set_layer "$STEP"
