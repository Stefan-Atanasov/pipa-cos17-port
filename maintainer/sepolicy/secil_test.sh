# usage: sh secil_test.sh <system_ext rules> <vendor rules>   (compile the on-device policy + extra rules like init)
V=$(cat /vendor/etc/selinux/plat_sepolicy_vers.txt)
T=/data/local/tmp/secil_t; rm -rf $T; mkdir -p $T
cat /system_ext/etc/selinux/system_ext_sepolicy.cil "$1" > $T/se.cil
cat /vendor/etc/selinux/vendor_sepolicy.cil "$2" > $T/ve.cil
set -- /system/etc/selinux/plat_sepolicy.cil /system/etc/selinux/mapping/$V.cil
[ -f /system/etc/selinux/mapping/$V.compat.cil ] && set -- "$@" /system/etc/selinux/mapping/$V.compat.cil
set -- "$@" $T/se.cil /system_ext/etc/selinux/mapping/$V.cil
[ -f /product/etc/selinux/product_sepolicy.cil ] && set -- "$@" /product/etc/selinux/product_sepolicy.cil /product/etc/selinux/mapping/$V.cil
set -- "$@" /vendor/etc/selinux/plat_pub_versioned.cil $T/ve.cil
[ -f /odm/etc/selinux/odm_sepolicy.cil ] && set -- "$@" /odm/etc/selinux/odm_sepolicy.cil
/system/bin/secilc -m -M true -G -N -c 30 "$@" -o $T/policy -f /dev/null; echo "secilc exit $?"
/system/bin/secilc -m -M true -G -c 30 "$@" -o $T/policy2 -f /dev/null 2>&1 | grep -A1 "neverallow check failed" | grep -c "^  (neverallow"
rm -rf $T
