#!/bin/sh
# make_from_stock.sh - assemble a beta4-like vendor or odm TREE from public/stock sources.
# Common engine; use make_vendor_from_stock.sh / make_odm_from_stock.sh (wrappers).
# Needs NO root. Does not build an image and does not set SELinux labels (see REPORT.md section "Labels").
#
# Inputs (environment variables, all are extracted trees = output of `fsck.erofs --extract=DIR IMG`;
# for a real build extract as root with `--xattrs --preserve` so the PixelOS labels survive):
#   KIND      v (vendor) or o (odm)                              [set by the wrapper]
#   OUT       output tree (must not exist or be empty)           [required]
#   PX        PixelOS tree of that partition                      [default /mnt/reference/pipa/reference/pixelos/{vendor,odm}]
#   HY IQ31 IQ10   hyperos1-stock / iqraos3.1 / iqraos_v1.0 roots (contain vendor/ and odm/ dirs) [default /mnt/reference/pipa/reference/<x>]
#   C06V C06O OPPO donor C.06 extracted vendor / odm trees        [default <root>/port-work/fromstock/x/c06v, .../c06o]
#   CORE      COS17/pipa_core dir                                  [default <COS17>/pipa_core]
#   PORT      COS17/port-rom dir                                   [default <COS17>/port-rom]
#   B4        (optional) extracted beta4 tree: last-resort source for the UNIQUE binaries (each is printed)
#   STANDIN   1 = for UNIQUE files with no beta4 tree: use the nearest stock counterpart (PixelOS/C.06 file, printed as
#             STANDIN, NOT byte-identical, newer/older build). Default 1 when B4 is empty, else 0.
# Steps: 1 copy PixelOS tree; 2 remove what beta4 removed; 3 copy files with a byte-identical stock source;
#        4 apply text patches (patches/<kind>/*.diff, raw byte diffs) and add new text files (*.new);
#        5 UNIQUE binaries from B4 (or STANDIN); 6 manifest (md5 per path) + comparison to B4 if given.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
KIND=${KIND:?KIND=v|o}
OUT=${OUT:?set OUT=<output dir>}
COS=$(cd "$HERE/../../.." && pwd); PROOT=${PIPA_ROOT:-$(cd "$COS/.." && pwd)}
R=${REF:-/mnt/reference/pipa/reference}   # extracted reference ROMs (REF=<dir> with pixelos/ hyperos1-stock/ iqraos3.1/ iqraos_v1.0/)
case $KIND in v) PD=vendor; DELTA=$HERE/vendor-delta.tsv; UNI=$HERE/unique-v.tsv; PAT=$HERE/patches/vendor;;
              o) PD=odm;    DELTA=$HERE/odm-delta.tsv;    UNI=$HERE/unique-o.tsv;    PAT=$HERE/patches/odm;; esac
PX=${PX:-$R/pixelos/$PD}
C06V=${C06V:-$PROOT/port-work/fromstock/x/c06v}; C06O=${C06O:-$PROOT/port-work/fromstock/x/c06o}
CORE=${CORE:-$COS/pipa_core}; PORT=${PORT:-$COS/port-rom}
B4=${B4:-}; [ -n "$B4" ] && STANDIN=${STANDIN:-0} || STANDIN=${STANDIN:-1}
TAB=$(printf '\t')
root() { # source key -> tree root
  case $1 in
    px_v) echo "$R/pixelos/vendor";; px_o) echo "$R/pixelos/odm";;
    hy_v) echo "${HY:-$R/hyperos1-stock}/vendor";; hy_o) echo "${HY:-$R/hyperos1-stock}/odm";;
    iq31_v) echo "${IQ31:-$R/iqraos3.1}/vendor";; iq31_o) echo "${IQ31:-$R/iqraos3.1}/odm";;
    iq10_v) echo "${IQ10:-$R/iqraos_v1.0}/vendor";; iq10_o) echo "${IQ10:-$R/iqraos_v1.0}/odm";;
    c06v) echo "$C06V";; c06o) echo "$C06O";; core) echo "$CORE";; port) echo "$PORT";;
    px) echo "$PX";;
    c06) [ $KIND = v ] && echo "$C06V" || echo "$C06O";;
    hy) echo "${HY:-$R/hyperos1-stock}/$PD";; iq31) echo "${IQ31:-$R/iqraos3.1}/$PD";;
    *) echo "/nonexistent";;
  esac
}
[ -d "$PX" ] || { echo "PX tree missing: $PX" >&2; exit 1; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then echo "OUT not empty: $OUT" >&2; exit 1; fi
mkdir -p "$OUT"
LOG=$OUT.log; : > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }

say "== 1 copy PixelOS $PD tree ($PX)"
cp -a "$PX/." "$OUT/"

say "== 2 remove what beta4 removed vs PixelOS"
n=0
while IFS=$TAB read -r p st sz src note; do
  [ "$st" = removed ] || continue
  rm -rf "$OUT/$p"; n=$((n+1))
done < "$DELTA"
say "   removed $n paths"

say "== 3 copy files with a byte-identical stock source"
n=0
while IFS=$TAB read -r p st sz src note; do
  case $st in added|modified) ;; *) continue;; esac
  [ "$src" = UNIQUE ] && continue
  k=${src%%:*}; sp=${src#*:}
  f=$(root "$k")/$sp
  [ -f "$f" ] || { say "   MISSING source $src for $p"; continue; }
  mkdir -p "$OUT/$(dirname "$p")"; cp -p "$f" "$OUT/$p"; n=$((n+1))
done < "$DELTA"
say "   copied $n files"

say "== 4 text patches and new text files"
# UNIQ columns: path status size kind counterpart detail ; counterpart 'px' = already in tree, 'xx(other base)' = copy base first
na=0; nn=0
while IFS=$TAB read -r p st sz kind cp detail; do
  [ "$kind" = text ] || continue
  # without beta4 binaries the PixelOS IPower is v6: keep the v6 vintf entry (beta4 text says v7)
  [ "$STANDIN" = 1 ] && [ -z "$B4" ] && [ "$p" = etc/vintf/manifest/android.hardware.power-service.lineage.xml ] && { say "   SKIP patch $p (stand-in binary is IPower v6)"; continue; }
  flat=$(echo "$p" | sed 's#/#__#g')
  case $cp in
    -) cp -p "$PAT/$flat.new" "$OUT/$p" 2>/dev/null || { mkdir -p "$OUT/$(dirname "$p")"; cp "$PAT/$flat.new" "$OUT/$p"; }; nn=$((nn+1));;
    px) patch --binary -s -p1 -d "$OUT" < "$PAT/$flat.diff" >>"$LOG" 2>&1 || say "   PATCH FAILED $p"; na=$((na+1));;
    *) k=${cp%%(*}; base=$(root "$k")/$p
       mkdir -p "$OUT/$(dirname "$p")"; cp "$base" "$OUT/$p"
       patch --binary -s -p1 -d "$OUT" < "$PAT/$flat.diff" >>"$LOG" 2>&1 || say "   PATCH FAILED $p"; na=$((na+1));;
  esac
done < "$UNI"
say "   patched $na, new $nn"

say "== 5 UNIQUE binaries (no stock source)"
nb=0; ns=0; nm=0
while IFS=$TAB read -r p st sz kind cp detail; do
  [ "$kind" = binary ] || continue
  if [ -n "$B4" ] && [ -f "$B4/$p" ]; then
    mkdir -p "$OUT/$(dirname "$p")"; cp -p "$B4/$p" "$OUT/$p"; say "   FROM-BETA4 $p ($sz)"; nb=$((nb+1))
  elif [ "$STANDIN" = 1 ] && [ "$cp" != - ]; then
    k=${cp%%(*}; f=$(root "$k")/$p
    if [ "$k" = pipa_core/facehal ]; then f=$CORE/facehal/$(basename "$p"); [ -f "$f" ] || f=$CORE/facehal/lib64/$(basename "$p"); fi
    if [ -f "$f" ]; then
      mkdir -p "$OUT/$(dirname "$p")"; cp -p "$f" "$OUT/$p"; say "   STANDIN($cp) $p [$detail]"; ns=$((ns+1))
    else say "   MISSING $p"; nm=$((nm+1)); fi
  else say "   MISSING $p ($sz, no counterpart)"; nm=$((nm+1)); fi
done < "$UNI"
say "   from-beta4 $nb, standin $ns, missing $nm"

if [ $nm -gt 0 ] && [ $KIND = v ] && [ -z "$B4" ]; then
  # services whose binaries are missing would crash-loop: drop their rc/vintf entries
  for f in etc/init/oplus_hal_odm.rc etc/vintf/manifest/manifest_oplus_stability.xml; do [ -e "$OUT/$f" ] && { rm -f "$OUT/$f"; say "   DROPPED orphan $f (oplus HAL binaries are beta4-only)"; }; done
fi

if [ $KIND = o ] && [ -z "$B4" ]; then
  # a stale precompiled policy (built for another plat/system_ext) must not be used: without it init compiles the cil at boot
  rm -f "$OUT"/etc/selinux/precompiled_sepolicy "$OUT"/etc/selinux/precompiled_sepolicy.*.sha256
  say "   DROPPED precompiled_sepolicy(+sha256): init compiles policy at boot (slower, but consistent with the ROM)"
fi

say "== 6 manifest"
( cd "$OUT" && find . \( -type f -o -type l \) | sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf 'LINK:%s\t%s\n' "$(readlink "$f")" "${f#./}"; else printf '%s\t%s\n' "$(md5sum < "$f" | cut -d' ' -f1)" "${f#./}"; fi
  done ) > "$OUT.manifest"
say "   $(wc -l < "$OUT.manifest") entries -> $OUT.manifest"
if [ -n "${CMP:-$B4}" ]; then B4C=${CMP:-$B4}
  ( cd "$B4C" && find . \( -type f -o -type l \) | sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf 'LINK:%s\t%s\n' "$(readlink "$f")" "${f#./}"; else printf '%s\t%s\n' "$(md5sum < "$f" | cut -d' ' -f1)" "${f#./}"; fi
  done ) > "$OUT.b4manifest"
  same=$(sort "$OUT.manifest" "$OUT.b4manifest" | uniq -d | wc -l)
  tot=$(wc -l < "$OUT.b4manifest")
  say "   identical to beta4: $same of $tot"
  cut -f2 "$OUT.manifest" | sort > "$OUT.p1"; cut -f2 "$OUT.b4manifest" | sort > "$OUT.p2"
  say "   only in assembled: $(comm -23 "$OUT.p1" "$OUT.p2" | wc -l)  only in beta4: $(comm -13 "$OUT.p1" "$OUT.p2" | wc -l)"
  sort "$OUT.manifest" "$OUT.b4manifest" | uniq -u | cut -f2 | sort -u > "$OUT.diffpaths"
  say "   differing paths listed in $OUT.diffpaths ($(wc -l < "$OUT.diffpaths"))"
  rm -f "$OUT.p1" "$OUT.p2"
fi
say "done. Labels/ownership/modes are NOT handled here: extract PX with --xattrs --preserve as root and relabel added files (see REPORT.md)."
