#!/bin/sh
# Phase 5b: a USB-C monitor is an extended ColorOS screen, not a mirror (BUGS-TODO 54; system_ext only).
#
# ColorOS (OplusConnectedDisplayUtils.hasFeatureConnectedDisplay) enables its connected-display mode only with the
# feature oplus.software.display_extended_mode AND >= 12 GB RAM (OplusConnectedDisplayManager.setRamSizeSupport),
# or with persist.wm.debug.enforce_display_extended_mode. pipa has 8 GB and the donor declares no such feature. With the
# prop and Settings.Secure mirror_built_in_display=0 (pipa_port sets it once, EXT_DISPLAY in config.prop) the monitor is
# its own screen with a taskbar (SecondaryDisplayLauncher); apps open full screen there. Tested live 2026-11-04 (GO27Q24).
# Not used: Android's native desktop windowing (persist.wm.debug.desktop_mode_enforce_device_restrictions=false): the
# ColorOS launcher crashes on its empty Desk tasks (NPE TaskInfo.origActivity, crash loop).
set -eu
. "$PORT/lib.sh"
STEP=5b

BP=$T/system_ext/etc/build.prop
forbid_grep '^persist.wm.debug.enforce_display_extended_mode=' "$BP"
{ cat "$BP"; printf '\n# pipa port 5b: ColorOS extended screen on a USB-C monitor (the stock check wants >= 12 GB RAM)\npersist.wm.debug.enforce_display_extended_mode=true\n'; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode
need_grep '^persist.wm.debug.enforce_display_extended_mode=true$' "$BP"
set_layer "$STEP"
