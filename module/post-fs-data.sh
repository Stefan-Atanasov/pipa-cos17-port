#!/system/bin/sh
# Bind-mount the replaced display files over the stock ones.
#
# This KernelSU 4.2 build has no module mount provider ("mount": "false" in
# `ksud module list`), so files under the module's system/ tree are NOT mounted.
# post-fs-data runs before the composer (QDCM calibration) and system_server
# (brightness table) start, so a plain bind mount in the global namespace is enough.
#
# KernelSU moves system/vendor and system/system_ext to the module root on
# install; Magisk keeps them under system/. Both layouts are handled.

MODDIR=${0%/*}
LOG=/data/local/tmp/pipa_power_tune.log

# Optional flags (the runtime guard reads the same file).
[ -f "$MODDIR/config.prop" ] && . "$MODDIR/config.prop"
FRAMEWORK_SENSOR_REROUTE=${FRAMEWORK_SENSOR_REROUTE:-1}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

[ "$(getprop ro.product.device)" = "pipa" ] || exit 0

bind() { # src target
    [ -f "$1" ] && [ -f "$2" ] || return
    # already in place? (mount tables can't be used: pipa_core's susfs
    # hide-sus-mnts hides these binds from /proc/*/mounts and mountinfo)
    cmp -s "$1" "$2" && return
    if mount -o bind "$1" "$2"; then
        log "bind $2 <- module"
    else
        log "bind $2 FAILED"
    fi
}

for part in vendor system_ext; do
    for base in "$MODDIR/$part" "$MODDIR/system/$part"; do
        [ -d "$base" ] && [ ! -L "$base" ] || continue
        for f in $(cd "$base" && find . -type f); do
            # libraries need their partition's label or the loading process cannot map them
            case "$part/$f" in
                vendor/*.so) chcon u:object_r:vendor_file:s0 "$base/${f#./}" 2>/dev/null ;;
                system_ext/*.so) chcon u:object_r:system_lib_file:s0 "$base/${f#./}" 2>/dev/null ;;
            esac
            bind "$base/${f#./}" "/$part/${f#./}"
        done
    done
done

# Framework reroute: ColorOS asks for OPPO's CCT sensor type (33171001); the
# patched jar asks for Xiaomi's tcs3701 front CCT (33171088) instead and feeds
# a fixed lux into the ambience filter (the Xiaomi event has no lux slot).
# Each patched jar is named after the md5 of the ROM jar it was built from
# (framework/<md5>.jar): beta4 3316594f…, C.06 2175feb9…; framework/aliases maps
# other ROM jars to one of those ("<rom md5> <base md5>", e.g. the rebuilt beta5
# ships C.06 with only the engineer fix, 7afeadb1…). Only the one that
# matches the running ROM is bound; a jar from another build would mix framework
# versions and bootloop system_server.
# A prebuilt oat/arm64/oplus-services.odex belongs to the stock jar. beta4 ships
# none; if one exists the bind is skipped unless FRAMEWORK_ALLOW_ODEX=1 (untested:
# ART should reject the stale odex and run from the jar).
FRAMEWORK_ALLOW_ODEX=${FRAMEWORK_ALLOW_ODEX:-0}
if [ "$FRAMEWORK_SENSOR_REROUTE" = "1" ]; then
    base=$(md5sum /system/framework/oplus-services.jar 2>/dev/null | cut -d' ' -f1)
    JAR="$MODDIR/framework/$base.jar"
    if [ ! -f "$JAR" ] && [ -f "$MODDIR/framework/aliases" ]; then
        alias=$(awk -v m="$base" '$1 == m {print $2}' "$MODDIR/framework/aliases")
        [ -n "$alias" ] && JAR="$MODDIR/framework/$alias.jar"
    fi
    if [ ! -f "$JAR" ]; then
        log "framework jar: no patched jar for base md5 $base, reroute skipped"
    elif [ -e /system/framework/oat/arm64/oplus-services.odex ] && [ "$FRAMEWORK_ALLOW_ODEX" != "1" ]; then
        log "framework jar: prebuilt oplus-services.odex present, reroute skipped (FRAMEWORK_ALLOW_ODEX=0)"
    else
        # the label matters: system_server cannot read a shell_data_file jar
        chmod 0644 "$JAR" 2>/dev/null
        chcon u:object_r:system_file:s0 "$JAR" 2>/dev/null
        bind "$JAR" /system/framework/oplus-services.jar
    fi
fi
