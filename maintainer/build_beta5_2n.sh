#!/bin/sh
# Phase 2n: faster QS -> Settings / app launch transitions, on top of 2m. Run as root:
#
#   sudo sh build_beta5_2n.sh
#
# * pipa_port SYSTEM_UX: system_server's android.anim / android.display / android.ui as UI First animator UX
#   (android.anim holds the WindowManager lock during window animations; Settings waited on it).
# * pipa_port SPEED_COMPILE: Settings, the Wi-Fi page, the launcher and SystemUI fully AOT-compiled once per build.
# * product build.prop: dalvik.vm.systemuicompilerfilter=speed (as on Pixels).
# 2026-10-24 QS -> Settings trace (4 launches): Settings 276-332 -> 226-261 ms, Wi-Fi page 221-354 -> 194-251 ms,
# SystemUI frames on time 52 -> 65 %.
#
# Input: port-work/${TAG}-2m/tree/{system,system_ext}, port-work/${TAG}-2m/img. Output: port-work/${TAG}-2n/.
set -eu
TAG=${TAG:-beta5}
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2m/img
W=$P/${TAG}-2n
HERE=$(cd "$(dirname "$0")" && pwd)
ROM=$HERE/../port-rom
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2m.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2m/tree/system" "$P/${TAG}-2m/tree/system_ext" "$W/tree/"
SE=$W/tree/system_ext
echo "== product: extract"
fsck.erofs --extract="$W/tree/product" --xattrs --preserve "$IMGSRC/product.img"
PR=$W/tree/product

# in place (cat >): owner, mode and SELinux label stay
echo "== pipa_port"
for f in service.sh config.prop; do
    cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"   # in place (cat >): owner, mode and SELinux label stay
    echo "updated system_ext/pipa_port/$f"
done
grep -q SYSTEM_UX "$SE/pipa_port/service.sh"

echo "== product build.prop: SystemUI compiler filter"
BP=$PR/etc/build.prop
grep -q 'dalvik.vm.systemuicompilerfilter' "$BP" && { echo "already patched"; exit 1; }
printf '%s\n' '' '# pipa port 2n: SystemUI fully AOT compiled (QS panel first-show hitches; as on Pixels)' \
    'dalvik.vm.systemuicompilerfilter=speed' >> "$BP"
tail -3 "$BP"

echo "== label check"
for t in system_ext product; do
    python3 -I "$HERE/tree_manifest.py" "$W/tree/$t" > "$W/report/$t.tsv"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/$t.tsv" | wc -l)
    echo "$t: $(wc -l < "$W/report/$t.tsv") entries, $n without a SELinux label"
    [ "$n" = 0 ] || exit 1
done

echo "== mkfs (system_ext, product)"
for t in system_ext product; do
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$t.img" "$W/tree/$t" > "$W/report/mkfs_$t.log" 2>&1
done
for p in system vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
ls -l "$W/img"

echo "== super"
cd "$W/img"
set --
for p in system system_ext product vendor odm; do set -- "$@" --partition "${p}_a:readonly:0:qti_dynamic_partitions_a"; done
for p in system system_ext product vendor odm; do
    set -- "$@" --partition "${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b" --image "${p}_b=$p.img"
done
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab \
    --device super:9126805504 \
    --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
    "$@" --sparse --output super.img 2>&1 | grep -v -e 'will resize' -e 'Invalid sparse' || true
ls -l super.img
md5sum super.img
chown -R "$OWNER" "$W/img" "$W/report"
echo "== done"
