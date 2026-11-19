#!/system/bin/sh
# Runs before the port service (pipa_port) starts: set its user override PEN_BT_ONLY=0 (step 6u switch).
F=/data/misc/pipa_port/config.prop
mkdir -p /data/misc/pipa_port
[ -f "$F" ] && grep -q '^PEN_BT_ONLY=0$' "$F" && exit 0
[ -f "$F" ] && sed -i '/^PEN_BT_ONLY=/d' "$F"
echo 'PEN_BT_ONLY=0' >> "$F"
