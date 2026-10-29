#!/bin/sh
# Phase 3a: privacy password, app lock and hidden apps work (BUGS-TODO B8), on top of 2z (system + system_ext).
#
# * system_ext/pipa_port/cryptoeng.jar + service.sh/config.prop (CRYPTOENG): ColorOS keeps the privacy password in
#   OPPO's TEE app behind vendor.oplus.hardware.cryptoeng.ICryptoeng/default, which pipa does not have. pipa_port
#   starts CryptoEngShim (maintainer/cryptoeng, built by its build.sh), which answers the same commands (enroll,
#   verify, modify, delete, get info) and keeps the records in /data/misc/pipa_port/cryptoeng. Online recovery
#   (OPPO account, e-mail) stays unsupported.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3a (early.sh clears the package cache).
#
# Old layer script: build_beta5_3a.sh
#NEEDS: "$HERE/cryptoeng/cryptoeng.jar" "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"
STEP=3a
CE_JAR=$HERE/cryptoeng/cryptoeng.jar
CE_MD5=2eb17a271c5864589c59ef287ea466c3   # maintainer/cryptoeng/build.sh (JDK 21, build-tools 37.0.0)
[ "$(md5sum "$CE_JAR" | cut -d' ' -f1)" = "$CE_MD5" ] || die "cryptoeng.jar md5 differs: run maintainer/cryptoeng/build.sh, update CE_MD5"

S=$T/system
SE=$T/system_ext

echo "== pipa_port: cryptoeng shim"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"
    echo "updated system_ext/pipa_port/$f"
done
need_grep 'app_process /system/bin CryptoEngShim' "$SE/pipa_port/service.sh"
need_grep '^CRYPTOENG=1$' "$SE/pipa_port/config.prop"
if grep -v '^[[:space:]]*#' "$SE/pipa_port/service.sh" | grep -q '$(settings get'; then echo '$(settings get ...) cannot work in the service'; exit 1; fi
A=$SE/pipa_port/cryptoeng.jar
cp "$CE_JAR" "$A"
chown 0:0 "$A"; chmod 644 "$A"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$A"
echo "cryptoeng.jar $CE_MD5"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"

