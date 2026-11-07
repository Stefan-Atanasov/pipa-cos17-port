# Xiaomi Pad 6 (pipa) Dolby speaker EQ: install check (KernelSU / SukiSU / APatch / Magisk)
SKIPUNZIP=0
STOCK=582003e70df30be8964df17610212ef3   # stock HyperOS 2 vendor/etc/dolby/dax-default.xml
OURS=c6413875ca78c292ce5b179822ca7215    # the same file with the speaker EQ
F=/vendor/etc/dolby/dax-default.xml
[ "$(getprop ro.product.vendor.device)" = pipa ] || [ "$(getprop ro.product.device)" = pipa ] || \
    abort "! This module is only for the Xiaomi Pad 6 (pipa)."
[ -f "$F" ] || abort "! $F not found: this ROM has no Dolby (DAX3)."
SUM=$(md5sum "$F" | cut -d' ' -f1)
case "$SUM" in
    $OURS) abort "! The speaker EQ is already in this ROM (ColorOS 17 port beta8 or later). Nothing to do." ;;
    $STOCK) ui_print "- Stock HyperOS 2 Dolby tuning found: OK" ;;
    *) abort "! Unknown Dolby tuning file (md5 $SUM). This module only replaces the stock HyperOS 2 file." ;;
esac
md5sum "$MODPATH/dax-default.xml" | grep -q "^$OURS" || abort "! Module file is damaged. Download it again."
set_perm "$MODPATH/dax-default.xml" 0 0 0644 u:object_r:vendor_configs_file:s0
ui_print "- After the reboot Dolby rebuilds its database once:"
ui_print "  Dolby settings and the Dolby equalizer go back to default one time."
