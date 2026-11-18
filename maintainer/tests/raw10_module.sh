#!/bin/bash
# BUGS 121 test: GCam HDR+ RAW10. Our vendor libgrallocutils (670fd5fd) treats RAW_OPAQUE/RAW10/RAW12 (0x24-0x26)
# as camx custom formats; libcamxexternalformatutils only knows 0x24 + 0x113.. -> error 1 for RAW10.
# PixelOS libgrallocutils (lib64 926727b9, lib 3be4847e) = same source, only 0x24.
# Test = KSU module whose post-fs-data.sh bind-mounts both libs (SukiSU 4.3 has no metamodule: system/ overlays
# do not apply). post-fs-data runs before class_start hal, so allocator/SF/camera load the new lib from the start.
#   bash raw10_module.sh install   (then reboot)
#   bash raw10_module.sh check     (after boot: md5 of the live libs)
#   bash raw10_module.sh remove    (then reboot) -- or TWRP: rm -rf /data/adb/modules/pipa_raw10_test
set -eu
A="adb -s 83836a90"
R=~/Documents/pipa/reference/pixelos/vendor
M=/data/adb/modules/pipa_raw10_test
T=$(mktemp -d)
case "${1:-}" in
install)
    printf 'id=pipa_raw10_test\nname=RAW10 gralloc test\nversion=1\nversionCode=1\nauthor=pipa\ndescription=temporary BUGS 121\n' > "$T/module.prop"
    cat > "$T/post-fs-data.sh" <<'EOF'
#!/system/bin/sh
MODDIR=${0%/*}
mount -o bind "$MODDIR/gu64.so" /vendor/lib64/libgrallocutils.so
mount -o bind "$MODDIR/gu32.so" /vendor/lib/libgrallocutils.so
EOF
    cp "$R/lib64/libgrallocutils.so" "$T/gu64.so"; cp "$R/lib/libgrallocutils.so" "$T/gu32.so"
    $A shell "rm -rf /data/local/tmp/raw10m; mkdir -p /data/local/tmp/raw10m"
    $A push "$T/." /data/local/tmp/raw10m/ >/dev/null
    $A shell "su -c 'rm -rf $M && cp -r /data/local/tmp/raw10m $M && chmod 644 $M/gu64.so $M/gu32.so $M/module.prop && chmod 755 $M/post-fs-data.sh && chcon u:object_r:same_process_hal_file:s0 $M/gu64.so $M/gu32.so && ls -lZ $M && md5sum $M/gu64.so $M/gu32.so'"
    echo "installed; reboot: adb -s 83836a90 reboot" ;;
check)
    $A shell "md5sum /vendor/lib64/libgrallocutils.so /vendor/lib/libgrallocutils.so" ;;
remove)
    $A shell "su -c 'rm -rf $M'"; echo "removed; reboot" ;;
*) echo "usage: $0 install|check|remove"; exit 1 ;;
esac
rm -rf "$T"
