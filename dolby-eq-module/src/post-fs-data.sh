# Bind-mount the EQ tuning over the vendor file (works without a KernelSU metamodule).
MODDIR=${0%/*}
F=/vendor/etc/dolby/dax-default.xml
[ -f "$MODDIR/disable" ] && exit 0
# only over the stock file (a ROM update can bring another tuning)
[ "$(md5sum "$F" | cut -d' ' -f1)" = 582003e70df30be8964df17610212ef3 ] || exit 0
chcon u:object_r:vendor_configs_file:s0 "$MODDIR/dax-default.xml"
mount -o bind "$MODDIR/dax-default.xml" "$F"
