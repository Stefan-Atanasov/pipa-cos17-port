#!/bin/sh
# swap_test.sh: make a TEST super.img = a finished port build (default pt128) whose vendor has the stock (PixelOS)
# build of the beta4-only binaries of one set. Handoff Part B, test B8-1 (BUGS 141).
#   sudo sh maintainer/fromstock/vendor/swap_test.sh <tag> <set>
#   set 1a: all binaries with a PixelOS counterpart at the same path, except the graphics/display chain, apps,
#           thermal configs and kernel modules (+ the PixelOS power HAL manifest if the power HAL binary is swapped)
#   set 1b: only the graphics/display chain (the PixelOS files of it; files without a PixelOS counterpart stay beta4)
# Content is written in place (cat new > old): the file keeps the label, owner and mode of the port build.
# A path whose file in the base build is not the beta4 file (a port step changed it) is skipped.
# Env: BASE (img dir of the base build), PX (PixelOS vendor tree), B4MD5 (beta4 vendor md5 manifest).
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root (labels)"; exit 1; }
[ $# = 2 ] || { sed -n 2,10p "$0"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); COS=$(cd "$HERE/../../.." && pwd); ROOT=${PIPA_ROOT:-$(cd "$COS/.." && pwd)}
TAG=$1; SET=$2
BASE=${BASE:-$ROOT/port-work/pt128/img}
PX=${PX:-/mnt/reference/pipa/reference/pixelos/vendor}
B4MD5=${B4MD5:-/mnt/reference/pipa/reference/analysis/inventory/cos17.vendor.md5}
W=$ROOT/port-work/$TAG; T=$W/tree/vendor; L=$W/report/swap.log
for f in "$BASE/vendor.img" "$BASE/system.img" "$B4MD5" "$HERE/unique-v.tsv"; do [ -e "$f" ] || { echo "missing $f"; exit 1; }; done
[ -d "$PX/lib64" ] || { echo "missing PixelOS vendor tree $PX"; exit 1; }
avail=$(df -P "$ROOT/port-work" | awk 'NR==2{print int($4/1048576)}'); [ "$avail" -ge 20 ] || { echo "only $avail GB free"; exit 1; }
RE=${READELF:-$(command -v llvm-readelf || command -v readelf || echo "$ROOT/port-work/kernel/clang-r547379/bin/llvm-readelf")}
GFX='egl/|adreno|Adreno|gralloc|mapper|composer|hwcomposer|display|qdMetaData|qdutils|qservice|libsdm|drm|vulkan|llvm|libkcl|libgsl|libCB|OpenCL|q3d|a650|gpu|libsde|snapalloc|memutils|libc2d|libsc-a|libEGL|libGLES|libgui|libui\.so|hdr|color'

rm -rf "$W"; mkdir -p "$W/img" "$W/report" "$W/tree"
fsck.erofs --extract="$T" --xattrs --preserve "$BASE/vendor.img" > "$W/report/extract.log" 2>&1
awk -F'\t' 'NR>1 && $4=="binary" && $5=="px" {print $1}' "$HERE/unique-v.tsv" |
	grep -v -E '\.apk$|/thermal-.*\.conf$|\.ko$|NOTICE|audio\.primary' > "$W/report/candidates.txt"
# Kept from the port build (BUGS 141 test results): the PixelOS wifi HAL tracks the interfaces differently
# ("Unknown iface name: wlan0", "No active wlan interfaces", 5 -> 25 warnings) and Wi-Fi dropped once after the
# p2p0 teardown (fs1a, 2026-11-19). EXCLUDE=<regex> replaces this list.
EXCLUDE=${EXCLUDE-'^bin/hw/android\.hardware\.wifi-service$'}
[ -n "$EXCLUDE" ] && { grep -v -E "$EXCLUDE" "$W/report/candidates.txt" > "$W/report/c2" || :; mv "$W/report/c2" "$W/report/candidates.txt"; }
case $SET in
	1a) grep -v -E "$GFX" "$W/report/candidates.txt" > "$W/report/set.txt" || :;;
	1b) grep -E "$GFX" "$W/report/candidates.txt" > "$W/report/set.txt" || :;;
	*) echo "set must be 1a or 1b"; exit 1;;
esac
n=0; skip=0; : > "$L"; : > "$W/report/replaced.txt"
while read -r p; do
	tf=$T/$p; src=$PX/$p
	if [ ! -f "$tf" ] || [ -L "$tf" ] || [ ! -f "$src" ]; then echo "SKIP missing   $p" >> "$L"; skip=$((skip+1)); continue; fi
	cur=$(md5sum < "$tf" | cut -c1-32); b4=$(awk -v q="./$p" '$2==q{print $1}' "$B4MD5")
	if [ "$cur" != "$b4" ]; then echo "SKIP port-edit $p" >> "$L"; skip=$((skip+1)); continue; fi
	cat "$src" > "$tf"; echo "$p" >> "$W/report/replaced.txt"; n=$((n+1))
done < "$W/report/set.txt"
# The vintf manifests stay the port's. Both power HAL builds implement IPower v7 (they link power-V7-ndk); the
# PixelOS manifest says 6, which is wrong, so it is not taken. Report the version of each swapped HAL vs its manifest
# (beta4 itself has health V5 with a manifest of 4: not new).
for b in $(grep '^bin/hw/' "$W/report/replaced.txt" || :); do
	for v in $("$RE" -d "$T/$b" | grep -o 'android\.hardware\.[a-z.]*-V[0-9]*-ndk' | grep -v -E 'common|fmq'); do
		nm=${v%-V*}; ver=${v##*-V}; ver=${ver%-ndk}
		mv=$(grep -rh -A2 "<name>$nm</name>" "$T/etc/vintf" 2>/dev/null | sed -n 's/.*<version>\([0-9-]*\)<.*/\1/p' | sort -u | tr '\n' ' ')
		echo "HAL $(basename "$b"): $nm binary V$ver, manifest ${mv:-(no version = 1)}" >> "$L"
	done
done
echo "set $SET: $n replaced, $skip skipped (of $(wc -l < "$W/report/set.txt"))" | tee -a "$L"
# every NEEDED library of a replaced ELF must exist in the new vendor (or be a system library that PixelOS also
# takes from system: not in the PixelOS vendor either)
miss=0
while read -r p; do
	case $p in *.xml) continue;; esac
	d=lib64; case $p in lib/*) d=lib;; esac
	for so in $("$RE" -d "$T/$p" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p'); do
		[ -e "$T/$d/$so" ] || [ -e "$T/$d/hw/$so" ] || [ -e "$T/$d/egl/$so" ] && continue
		if [ -e "$PX/$d/$so" ] || [ -e "$PX/$d/hw/$so" ]; then echo "NEEDED missing: $p -> $so" | tee -a "$L"; miss=$((miss+1)); fi
	done
done < "$W/report/replaced.txt"
[ "$miss" = 0 ] || { echo "$miss missing libraries: stop (see $L)"; exit 1; }
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/vendor.img" "$T" > "$W/report/mkfs_vendor.log" 2>&1
for p in system system_ext product odm; do ln "$BASE/$p.img" "$W/img/$p.img" 2>/dev/null || cp "$BASE/$p.img" "$W/img/"; done
cd "$W/img"
set --
for p in system system_ext product vendor odm; do set -- "$@" --partition "${p}_a:readonly:0:qti_dynamic_partitions_a"; done
for p in system system_ext product vendor odm; do
	set -- "$@" --partition "${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b" --image "${p}_b=$p.img"
done
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab --device super:9126805504 \
	--group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
	"$@" --sparse --output super.img > "$W/report/lpmake.log" 2>&1 || { cat "$W/report/lpmake.log"; exit 1; }
rm -rf "$W/tree"
chown -R "$(stat -c %u:%g "$COS")" "$W"
echo "== done: $W/img/super.img"; echo "md5 $(md5sum < super.img | cut -c1-32)"
