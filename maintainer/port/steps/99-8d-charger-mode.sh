#!/bin/sh
# Phase 8d (2026-11-20, BUGS 152): offline charging animation. Charger mode starts the charger service again,
# as on stock HyperOS, instead of OPPO's QuickBoot.
#
# * Power off + charger: the bootloader starts Android with androidboot.mode=charger. The ColorOS init.rc has
#   `on charger && property:ro.boot.hardware=qcom` with `class_start charger` commented out and
#   `setprop service.bootanim.exit 1` + `trigger late-init` instead (OPPO QuickBoot: everything but zygote). The OPPO
#   charge screen is not on pipa: SurfaceFlinger starts, bootanimation exits ("do not play bootanimation at charger
#   mode"), the Xiaomi logo stays, no adb. pstore of such a boot: port-work/device-captures/charger-mode-20261120/.
# * Stock HyperOS init.rc: `on charger` -> `class_start charger`. The Xiaomi vendor has `vendor.charger`
#   (android.hardware.health-service.qti --charger, class charger, u:r:charger_vendor:s0, images in
#   /vendor/etc/res/images/charger). late-init must not run as well: SurfaceFlinger would hold the display.
# * Holding the power key in the charger UI sets sys.boot_from_charger_mode=1; the AOSP block in init.rc
#   (class_stop charger + trigger late-init) is unchanged.
set -eu
. "$PORT/lib.sh"
F=$T/system/system/etc/init/hw/init.rc
[ -f "$F" ] || die "no $F"
python3 -I - "$F" "$R/init.rc.charger" <<'EOF'
import re, sys
src, out = sys.argv[1], sys.argv[2]
s = open(src).read()
head = 'on charger && property:ro.boot.hardware=qcom\n'
i = s.find(head)
assert i >= 0 and s.count(head) == 1, 'qcom charger block not found once'
j = s.find('\non ', i + len(head))          # next action block
block = s[i:j if j > 0 else len(s)]
old = '    setprop service.bootanim.exit 1\n    trigger late-init\n'
assert block.count(old) == 1, 'QuickBoot commands not found in the qcom charger block'
new_block = block.replace(old, '    # pipa (8d): stock charger UI (vendor.charger), as on HyperOS\n    class_start charger\n')
s = s[:i] + new_block + s[i + len(block):]
open(out, 'w').write(s)
print('init.rc: qcom charger block -> class_start charger')
EOF
cat "$R/init.rc.charger" > "$F"   # in place: owner, mode and SELinux label stay
grep -n -A8 '^on charger && property:ro.boot.hardware=qcom' "$F"
