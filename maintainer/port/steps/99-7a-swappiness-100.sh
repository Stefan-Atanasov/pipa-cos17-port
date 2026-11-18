#!/bin/sh
# Step 7a (BUGS 118, user 2026-11-15 "value between 60 and 200, best overall"): swappiness 100 on > 6 GB pipa.
# OPPO's product/bin/init.oplus.nandswap.sh (6t) sets vm_swappiness 200 for SM8250 > 6 GB (zstd); hybridswapd keeps the
# kernel default 200. HyperOS pipa uses 180, the pt68 era 60. A/B 2026-11-15, pt97 + walt-hi1, same boot, traced_heavy
# (2 runs per value) + retention test (12 apps incl. PUBG reopened twice, am start -W):
#   200: SystemUI janky 10.5 %, launcher FrameTimeline janky 38 %, dropped 29, allocstall ~2500, round-1 cold 4 / 6.0 s
#   100: SystemUI 7.5 %, FT 31 %, dropped 31, allocstall ~60, round-1 cold 2 / 3.6 s
#    60: SystemUI 7.2 %, FT 28 %, dropped 27, allocstall ~15, round-1 cold 3 / 3.9 s
# 100 = smoothness of 60 within noise, best app retention. 6 GB (OPPO 160) unchanged (not testable here).
# Sets vm_swappiness and swapd_swappiness (hybridswapd) to 100 in that branch; direct_swappiness stays 60.
set -eu
. "$PORT/lib.sh"
STEP=7a

N=$T/product/bin/init.oplus.nandswap.sh
forbid_grep 'pipa port 7a' "$N"
replace_once "$N" '\t\t# SM8350 | SM7325 | SM8250 | SM7250 | SM7225\n\t\t\tif [[ $mem_total -gt 6291456 ]]; then\n\t\t\t\tcomp_algorithm="zstd"\n\t\t\t\tvm_swappiness=200\n' \
    '\t\t# SM8350 | SM7325 | SM8250 | SM7250 | SM7225\n\t\t\tif [[ $mem_total -gt 6291456 ]]; then\n\t\t\t\tcomp_algorithm="zstd"\n\t\t\t\t# pipa port 7a: 100 instead of 200 (vm + hybridswapd; BUGS 118)\n\t\t\t\tvm_swappiness=100\n\t\t\t\tswapd_swappiness=100\n'
replace_once "$N" '\techo "vm_swappiness=${vm_swappiness}" > /proc/${oplus_path}/swappiness_para\n}\n' \
    '\techo "vm_swappiness=${vm_swappiness}" > /proc/${oplus_path}/swappiness_para\n\t# pipa port 7a\n\t[ -n "${swapd_swappiness:-}" ] && echo "swapd_swappiness=${swapd_swappiness}" > /proc/${oplus_path}/swappiness_para\n}\n'
need_grep 'vm_swappiness=100' "$N"
need_grep 'swapd_swappiness=${swapd_swappiness}' "$N"
sh -n "$N" 2>/dev/null || bash -n "$N"

set_layer "$STEP"
