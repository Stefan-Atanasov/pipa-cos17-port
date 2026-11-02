#!/bin/sh
# Phase 4i: Display > "keep the screen on while you look at it" works (BUGS-TODO 57; odm, vendor, my_product).
#
# The setting is AOSP screen attention (secure adaptive_sleep). Its service is OPPO's AONService
# (com.aiunit.aon/.AONAttentionService): front camera frames into a TFLite face model through OPPO's libaiboost.
# * odm/lib64/libaiboost.so from the C.06 odm (needs only bionic libs). The pinned beta4 odm has none, and
#   libaiboost_jni.so logged: dlopen failed: library "/odm/lib64/libaiboost.so" not found. So no model loaded
#   ("engine off or model not ready"), no face was found and the screen went off at the normal timeout.
# * vendor/etc/public.libraries.txt: libaiboost.so (as in the C.06 vendor), so the app may load it.
# * my_product AppFeature com.aiunit.aon.is_cpu_support_only=true: without it AONService picks the Qualcomm NPU path,
#   and AIBoost_Create crashes (SIGSEGV) on the SM8250 DSP. On the CPU one frame takes about 33 ms, and the check
#   runs only a few seconds before the screen timeout.
# Tested live 2026-11-02 on pt22 (bind mounts + zygote restart): 30 s timeout, AttentionDetector onSuccess: 1
# (present) twice, the screen stayed on; without the AppFeature: crash, "Failed to check attention: 3".
#NEEDS: "$P/donor-c06-vendor/odm.img"
set -eu
. "$PORT/lib.sh"
STEP=4i
C06_VENDOR=$P/donor-c06-vendor
[ -f "$C06_VENDOR/odm.img" ] || die "C.06 odm image missing: $C06_VENDOR"

L=$T/odm/lib64/libaiboost.so
[ -e "$L" ] && die "already in odm: lib64/libaiboost.so"
dump.erofs --cat --path=/lib64/libaiboost.so "$C06_VENDOR/odm.img" > "$L"
[ -s "$L" ] || die "libaiboost.so not in the C.06 odm"
chown 0:0 "$L"; chmod 644 "$L"
setfattr -n security.selinux -v u:object_r:same_process_hal_file:s0 "$L"
echo "added   odm/lib64/libaiboost.so ($(md5sum < "$L" | cut -c1-8))"

PL=$T/vendor/etc/public.libraries.txt
forbid_grep '^libaiboost.so' "$PL"
{ cat "$PL"; echo libaiboost.so; } > "$R/public.libraries.txt.new"
cat "$R/public.libraries.txt.new" > "$PL"   # same inode: label, owner and mode kept
echo "edited  vendor/etc/public.libraries.txt"

AF=$T/system/my_product/etc/extension/com.oplus.app-features.xml
need_grep '</extend_features>' "$AF"
forbid_grep 'com.aiunit.aon.is_cpu_support_only' "$AF"
replace_once "$AF" '</extend_features>' '	<app_feature name="com.aiunit.aon.is_cpu_support_only" args="boolean:true"/>
</extend_features>'
need_grep 'com.aiunit.aon.is_cpu_support_only" args="boolean:true"' "$AF"
echo "edited  my_product/etc/extension/com.oplus.app-features.xml"
set_layer "$STEP"
