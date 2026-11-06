#!/bin/sh
# Phase 5x (beta7.2, tester report 2026-11-06, BUGS-TODO 79): fewer log lines and less wasted work, no log calls
# stripped wholesale (a tester did that in the framework and got system_server crashes without crash logs).
#
# * my_product/etc/power_profile/power_profile.xml: the cpu.* part was the donor's (2 clusters 6+2, 32 speed steps);
#   pipa has 3 clusters 4+3+1 and 56 steps (/proc/uid_time_in_state). OPPO OStats (CpuCalc) logged an error for every
#   sample ("cpuFreqTimeMs.length > CPU_WEIGHT.length", ~500 lines per minute of use) and Android's per-app power
#   estimate used wrong cores and speeds. Now cpu.* from stock HyperOS pipa (maintainer/power_profile, the rest is
#   OPPO's file with beta4's battery.capacity 8840).
# * logspam/patch_logspam.py table 5x (on the 4h jars, same-size dex edits):
#   - oplus-framework.jar UAHPerfManager.uahEventAcquire and tansSa2Event -> -1, getFeatureStatus -> 0 at once: the native client
#     looked up the absent urcc HAL each time and logged 2 errors (~230 lines per minute of use). 4h only covered the
#     Java getAidlService path. Boot jar: odrefresh compiles a new boot image on the first boot (as in 3o/4h).
#   - oplus-services.jar: QosScheduler "getScenario failed" / "executeSceneQosStrategy get scenario failed" and
#     SmartWindowScene "invalid window type" warnings removed (scenes 2 and 5 have no rule in OPPO's own scene
#     config: stock behaviour, the QoS scheduler itself works).
# * system_ext_property_contexts: 11 empty vendor props (ro.vendor.oplus.regionmark, market.name, ...; pt67 test:
#   + 2 codec trace props read by every media app) were
#   vendor_default_prop, so each app read logged "Access denied finding property" (~180 per minute). Now
#   exported_system_prop (readable, still empty). Nothing sets them (checked on pt66).
# * rules_5x_system_ext.cil: pipa_port may set persist.log.tag; audioserver may read /proc/<system_server> (OPPO
#   MMListServiceParser, tester dmesg). secilc exit 0, neverallow 76 (= without the rules).
# * port-rom (step 2e copies it): service.sh log_check, config LOG_QUIET=1: persist.log.tag=I (debug/verbose lines are
#   dropped in each process) unless global pipa_verbose_logs=1. helper 1.2 (step 2d): Quick Settings tile "Logs"
#   Quiet/Verbose.
#NEEDS: "$HERE/logspam/patch_logspam.py" "$HERE/jar-edits/venv/bin/python" "$HERE/power_profile/power_profile.xml" "$HERE/sepolicy/rules_5x_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=5x

# power profile
PP=$T/system/my_product/etc/power_profile/power_profile.xml
[ -f "$PP" ] || die "power profile missing: $PP"
need_grep 'name="battery.capacity">8840<' "$PP"
need_grep 'cpu.core_speeds.cluster2' "$HERE/power_profile/power_profile.xml"
cat "$HERE/power_profile/power_profile.xml" > "$PP"   # in place: owner, mode and SELinux label stay
need_grep 'pipa port 5x' "$PP"

# jars (on top of 4h)
F=$T/system/system/framework
for j in oplus-framework oplus-services; do
    echo "== $j.jar"
    "$HERE/jar-edits/venv/bin/python" -I "$HERE/logspam/patch_logspam.py" "$F/$j.jar" "$R/$j.jar" 5x 2>&1 | grep -v DEBUG
    [ -s "$R/$j.jar" ] || die "patch_logspam 5x failed: $j.jar"
    cat "$R/$j.jar" > "$F/$j.jar"
    rm -f "$R/$j.jar"
    for o in "$F/oat"/*/"$j".*; do if [ -e "$o" ]; then rm -v "$o"; fi; done
done

# property contexts
PC=$T/system_ext/etc/selinux/system_ext_property_contexts
[ -f "$PC" ] || die "missing: $PC"
forbid_grep 'pipa port 5x' "$PC"
{
    cat "$PC"
    printf '\n# pipa port 5x: empty OPPO vendor props apps ask for (were vendor_default_prop: "Access denied" per read)\n'
    for p in ro.vendor.oplus.regionmark ro.vendor.oppo.regionmark ro.vendor.oplus.market.name \
             ro.vendor.oplus.market.enname ro.vendor.oplus.operator ro.vendor.oplus.gundam \
             ro.vendor.oplus.exp.version ro.vendor.oplus.euex.country ro.odm.prev.product.name \
             persist.vendor.media.c2.frameworks.buffercount.trace vendor.debug.stagefright.mediacodec.trace; do
        printf '%s u:object_r:exported_system_prop:s0 exact string\n' "$p"
    done
} > "$R/pc.new"
cat "$R/pc.new" > "$PC"; rm -f "$R/pc.new"
need_grep 'ro.vendor.oplus.market.name u:object_r:exported_system_prop' "$PC"

# SELinux rules
SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 5x" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_5x_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 5x" "$SE/$f"
    echo "edited  system_ext/etc/selinux/$f"
done

# port-rom and helper parts (copied by 2e / 2d)
need_grep 'log_check()' "$T/system_ext/pipa_port/service.sh"
need_grep '^LOG_QUIET=1' "$T/system_ext/pipa_port/config.prop"
set_layer "$STEP"
