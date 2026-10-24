#!/system/bin/sh
# Magisk / KernelSU installer hook.
# KernelSU drops the exec bit on unzip, but it runs service.sh via `sh`, so
# this is only for convenience when inspecting the module from a shell.
SKIPUNZIP=0

chmod 0755 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/customize.sh" "$MODPATH/uninstall.sh" 2>/dev/null
chmod 0644 "$MODPATH/module.prop" "$MODPATH/config.prop" "$MODPATH/README.md" 2>/dev/null

# Replaced vendor/display files must carry the stock SELinux labels, otherwise
# the vendor composer (QDCM calibration), audioserver (volume curves) or
# system_server may be denied reading them and silently fall back.
for f in "$MODPATH"/system/vendor/etc/*.xml; do
    [ -f "$f" ] && chmod 0644 "$f" && chcon u:object_r:vendor_configs_file:s0 "$f"
done
# Patched audio HAL (speaker left/right in flipped landscape, module README 14):
# the HAL service cannot map a library without the vendor_file label.
for f in "$MODPATH"/system/vendor/lib/hw/*.so; do
    [ -f "$f" ] && chmod 0644 "$f" && chcon u:object_r:vendor_file:s0 "$f"
done
f="$MODPATH/system/system_ext/etc/display_brightness_config_default.xml"
[ -f "$f" ] && chmod 0644 "$f" && chcon u:object_r:system_file:s0 "$f"

# Patched framework jar (CCT sensor reroute, module README 12). post-fs-data
# repeats the chcon right before the bind, in case KernelSU moved the file.
for f in "$MODPATH"/framework/*.jar; do
    [ -f "$f" ] && chmod 0644 "$f" && chcon u:object_r:system_file:s0 "$f"
done

# tools/ is documentation for the port developer, not needed on the device
rm -rf "$MODPATH/tools"
