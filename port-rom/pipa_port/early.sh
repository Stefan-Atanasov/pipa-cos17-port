#!/system/bin/sh
# pipa_port early boot (post-fs-data, before zygote), run by init via exec in pipa_port.rc.
# From the pipa_port module's post-fs-data.sh; the virtual modem daemons are init services,
# traced is off by build.prop, susfs root hiding stays a module (pipa_susfs).

# stale pid files from the last boot (a reused pid would block the restart)
rm -f /data/local/tmp/pipa_pen_keys.pid /data/local/tmp/pipa_port.pid

# /metadata is only 58 MB; ColorOS bootcap writes ~20 MB per boot until aconfig hits StorageFull.
rm -rf /metadata/bootcap /metadata/portdiag

# Rounded-corner overlay idmap: /product/overlay is an overlayfs merge that includes
# /my_product/overlay, so idmap2d names the idmap after /product/overlay/... while
# OverlayManager looks for /my_product/overlay/... -> STATE_NO_IDMAP. Create the expected one
# before zygote loads the system assets.
CID=/data/resource-cache/my_product@overlay@PipaCornersOverlay.apk@idmap
CORNER_APK=/my_product/overlay/PipaCornersOverlay.apk
if [ ! -f "$CID" ] && [ -f "$CORNER_APK" ]; then
    idmap2 create --target-apk-path /system/framework/framework-res.apk \
        --overlay-apk-path "$CORNER_APK" --idmap-path "$CID" --ignore-overlayable 2>/dev/null &&
        chown system:system "$CID" && chmod 0644 "$CID"
fi
exit 0
