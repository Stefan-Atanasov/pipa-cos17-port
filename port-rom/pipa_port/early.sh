#!/system/bin/sh
# pipa_port early boot (post-fs-data, before zygote), run by init via exec in pipa_port.rc.
# From the pipa_port module's post-fs-data.sh; the virtual modem daemons are init services,
# traced is off by build.prop, susfs root hiding stays a module (pipa_susfs).

# stale pid files from the last boot (a reused pid would block the restart)
rm -f /data/local/tmp/pipa_pen_keys.pid /data/local/tmp/pipa_port.pid

# /metadata is only 58 MB; ColorOS bootcap writes ~20 MB per boot until aconfig hits StorageFull.
rm -rf /metadata/bootcap /metadata/portdiag

# Package parse cache (BUGS-TODO 14): the layers build with mkfs.erofs -T0 (all file times 0) and keep the build
# fingerprint, so PackageManager would keep the cached manifest of a changed system APK. Each layer sets
# ro.pipa.port.layer in system_ext/etc/build.prop; clear the cache once when it changes (before zygote/PMS).
L=$(getprop ro.pipa.port.layer)
if [ -n "$L" ] && [ "$L" != "$(cat /data/misc/pipa_port/pkgcache_layer 2>/dev/null)" ]; then
    rm -rf /data/system/package_cache/*
    echo "$L" > /data/misc/pipa_port/pkgcache_layer
fi

# OPPO OIFace (frame/thread booster, /system_ext/bin/oiface) moves threads into /dev/cpuset/oiface_fg, oiface_fg+ and
# oiface_bg, which OPPO's vendor init creates; pipa's Xiaomi vendor does not ("directSetTask: get cpuset path
# failed" on every app switch). OIFace writes the CPU masks itself (fg 4-6, fg+ 4-7, bg 0-3); it starts later (class hal).
for g in oiface_fg oiface_fg+ oiface_bg; do
    if mkdir -p "/dev/cpuset/$g" 2>/dev/null; then
        cat /dev/cpuset/mems > "/dev/cpuset/$g/mems"; cat /dev/cpuset/cpus > "/dev/cpuset/$g/cpus"
        chown -R root:system "/dev/cpuset/$g"; chmod 0775 "/dev/cpuset/$g"
        chmod 0664 "/dev/cpuset/$g/tasks" "/dev/cpuset/$g/cpus" "/dev/cpuset/$g/cgroup.procs"
    fi
done

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
