#!/bin/sh
# Phase 4j: a USB-C monitor is enabled when it connects (BUGS-TODO 54; system_ext only).
#
# Android 17 adds an external display disabled and waits for user consent (ExternalDisplayPolicy). ColorOS CN shows
# no consent dialog (OplusConnectedDisplayManager: "displayRecord not found"; its desktop mode needs >= 12 GB RAM),
# so the display stayed off, the composer never completed the connect and the kernel logged "connect timeout".
# persist.sys.display.enable_on_connect.external_force=true makes ExternalDisplayPolicy.shouldAutoEnable() true
# (also on user builds). Tested live 2026-11-02 on pt22 with a GO27Q24: "External display is enabled by default,
# bypassing user consent", display EXTERNAL enabled, WindowManager mirrors display 0, no more "connect timeout".
# Still open: that monitor drops HPD about 2 s after each stream start (kernel side, BUGS-TODO 54).
set -eu
. "$PORT/lib.sh"
STEP=4j

BP=$T/system_ext/etc/build.prop
forbid_grep '^persist.sys.display.enable_on_connect.external_force=' "$BP"
{ cat "$BP"; printf '\n# pipa port 4j: enable a USB-C monitor without the consent dialog that ColorOS does not show\npersist.sys.display.enable_on_connect.external_force=true\n'; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode
need_grep '^persist.sys.display.enable_on_connect.external_force=true$' "$BP"
set_layer "$STEP"
