#!/bin/sh
# Phase 2n: faster QS -> Settings / app launch transitions, on top of 2m.
#
# * pipa_port SYSTEM_UX: system_server's android.anim / android.display / android.ui as UI First animator UX
#   (android.anim holds the WindowManager lock during window animations; Settings waited on it).
# * pipa_port SPEED_COMPILE: Settings, the Wi-Fi page, the launcher and SystemUI fully AOT-compiled once per build.
# * product build.prop: dalvik.vm.systemuicompilerfilter=speed (as on Pixels).
# 2026-10-24 QS -> Settings trace (4 launches): Settings 276-332 -> 226-261 ms, Wi-Fi page 221-354 -> 194-251 ms,
# SystemUI frames on time 52 -> 65 %.
#
# Old layer script: build_beta5_2n.sh
#NEEDS: "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop"
set -eu
. "$PORT/lib.sh"

SE=$T/system_ext
PR=$T/product

# in place (cat >): owner, mode and SELinux label stay
echo "== pipa_port"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
need_grep SYSTEM_UX "$SE/pipa_port/service.sh"

echo "== product build.prop: SystemUI compiler filter"
BP=$PR/etc/build.prop
grep -q 'dalvik.vm.systemuicompilerfilter' "$BP" && { echo "already patched"; exit 1; }
printf '%s\n' '' '# pipa port 2n: SystemUI fully AOT compiled (QS panel first-show hitches; as on Pixels)' \
    'dalvik.vm.systemuicompilerfilter=speed' >> "$BP"
tail -3 "$BP"

