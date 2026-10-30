#!/bin/sh
# Phase 2u: SukiSU-Ultra manager 4.2.1-r1 preinstalled as a removable app, on top of 2t (system + system_ext).
#
# * system/my_stock/del-app/SukiSU/SukiSU.apk: ColorOS installs the del-app APKs as normal, removable apps (like
#   Calculator and Clock). After a clean flash the manager that matches the kernel's SukiSU (4.2.1-r1) is there; the
#   user opens it once to install ksud. The user can update or uninstall it.
# * system_ext/etc/build.prop: ro.pipa.port.layer=2u (early.sh clears the package cache).
#
# SKIPPED BY DEFAULT. In the old chain the layers after 2u are NOT built on 2u: 2v takes its system_ext
# from 2t, and 2w takes its system from 2s. So the 3h images have no del-app/SukiSU (KernelSU finds its
# manager only under /data/app, so the preload gave no root; 2w installs the manager from pipa_port instead).
# To get the same result in one tree, this step does nothing unless PORT_WITH_2U=1 is set. With it, the
# preload stays in the final image and ro.pipa.port.layer is set to 2u until 2v replaces it.
#
# Old layer script: build_beta5_2u.sh
#OPTIONAL: PORT_WITH_2U
#NEEDS: "$HERE/../kernel/sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk"
set -eu
. "$PORT/lib.sh"
STEP=2u

if [ "${PORT_WITH_2U:-0}" != 1 ]; then
    echo "2u skipped: the old chain does not carry 2u into 2v and later (set PORT_WITH_2U=1 to apply it)"
    exit 0
fi

KSU_APK=$HERE/../kernel/sukisu-v4.2.1-r1/SukiSU_v4.2.1-r1_41049-release.apk
[ -f "$KSU_APK" ] || die "SukiSU manager APK missing: $KSU_APK"
KSU_MD5=$(md5sum "$KSU_APK" | cut -d' ' -f1)

S=$T/system
SE=$T/system_ext

echo "== SukiSU manager 4.2.1-r1 as a removable preload (my_stock/del-app)"
D=$S/my_stock/del-app/SukiSU
[ ! -e "$D" ] || die "$D exists already"
mkdir -p "$D"
cp "$KSU_APK" "$D/SukiSU.apk"
chown 0:0 "$D" "$D/SukiSU.apk"
chmod 755 "$D"; chmod 644 "$D/SukiSU.apk"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$D"
setfattr -n security.selinux -v u:object_r:system_file:s0 "$D/SukiSU.apk"
md5sum "$D/SukiSU.apk"
[ "$(md5sum "$D/SukiSU.apk" | cut -d' ' -f1)" = "$KSU_MD5" ] || die "SukiSU.apk copy has a wrong md5"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
