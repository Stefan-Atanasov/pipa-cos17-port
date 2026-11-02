#!/bin/sh
# Phase 4n: enable OPPO QoS scheduling (BUGS-TODO 58 and 43; system_ext only).
#
# system_server loads libQosSched_Jni.so and qos_sched.so in its own process.
# Label the QoS proc nodes and permit access from system_server.
# Enable the feature with ro.oplus.osense.uaf_qos_enable.
# This needs kernel walt-r12+. Older kernels do not have the nodes.
# On a failed open, qos_sched.so logs the error and returns -1. It does not crash.
# Existing platform rules permit the writes to /dev/cpuctl cgroup files.
#NEEDS: "$HERE/uifirst-policy/qos_block.cil"
set -eu
. "$PORT/lib.sh"
STEP=4n

SE=$T/system_ext

echo "== SELinux: OPPO QoS proc nodes"
for f in etc/selinux/system_ext_sepolicy.cil etc/selinux/system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || { echo "skip    $f (absent)"; continue; }
    if grep -q 'oplus_qos_sched_proc' "$SE/$f"; then echo "$f: already patched"; exit 1; fi
    # in place (cat >>): owner, mode and SELinux label stay
    cat "$HERE/uifirst-policy/qos_block.cil" >> "$SE/$f"
    echo "edited  system_ext/$f (+$(wc -l < "$HERE/uifirst-policy/qos_block.cil") lines)"
done

BP=$T/system_ext/etc/build.prop
forbid_grep '^ro\.oplus\.osense\.uaf_qos_enable=' "$BP"
{ cat "$BP"; printf '\n# pipa port 4n: OPPO QoS scheduling needs kernel walt-r12+\nro.oplus.osense.uaf_qos_enable=true\n'; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode
set_layer "$STEP"
