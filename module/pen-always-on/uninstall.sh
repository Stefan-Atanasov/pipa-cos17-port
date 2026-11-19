#!/system/bin/sh
# Back to stock: pen input only while a Bluetooth pen is connected.
F=/data/misc/pipa_port/config.prop
[ -f "$F" ] && sed -i '/^PEN_BT_ONLY=/d' "$F"
