#!/bin/sh
# Step 9e (2026-11-25, BUGS 193): Virtual A/B compression (VABC) with userspace snapshots for our OTA installs.
# Install test 2026-11-25: the Android 16 libsnapshot in our system refuses legacy Virtual A/B updates ("Using legacy
# Virtual A/B (dm-snapshot)" -> "Cannot create update snapshots"); the HyperOS vendor of pipa sets only
# ro.virtual_ab.enabled=true. The kernel has CONFIG_DM_USER=y; the boot ramdisk gets a first-stage snapuserd
# (maintainer/kernel/add_snapuserd.sh, boot-walt-hi16-su.img); payloads carry virtual_ab_compression=true, method none
# (maintainer/ota/make_payload.sh, as AOSP ota_from_raw_img.py). The props only change OTA installs, not normal boots.
set -eu
. "$PORT/lib.sh"
STEP=9e
V=$T/vendor/build.prop
[ -f "$V" ] || die "no $V"
need_grep '^ro.virtual_ab.enabled=true' "$V"
forbid_grep '^ro.virtual_ab.compression.enabled=' "$V"
printf '%s\n' '' '# pipa port 9e (BUGS 193): VABC with userspace snapshots for A/B OTA installs' \
    'ro.virtual_ab.compression.enabled=true' 'ro.virtual_ab.userspace.snapshots.enabled=true' >> "$V"
need_grep '^ro.virtual_ab.compression.enabled=true' "$V"
need_grep '^ro.virtual_ab.userspace.snapshots.enabled=true' "$V"
echo "vendor build.prop: VABC + userspace snapshots on"
