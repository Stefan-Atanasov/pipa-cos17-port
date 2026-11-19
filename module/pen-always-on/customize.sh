SKIPUNZIP=0
if [ ! -f /system_ext/pipa_port/service.sh ] || ! grep -q PEN_BT_ONLY /system_ext/pipa_port/service.sh; then
  ui_print "! This is not the ColorOS 17 port for Xiaomi Pad 6 (v9 or newer). Abort."
  abort "! Wrong ROM"
fi
set_perm $MODPATH/post-fs-data.sh 0 0 0755
set_perm $MODPATH/uninstall.sh 0 0 0755
ui_print "- Pen input stays on for pens without Bluetooth (after reboot)."
ui_print "- Uninstall the module and reboot to go back to stock."
