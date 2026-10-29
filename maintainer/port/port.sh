#!/bin/sh
# Build the port (ROM super.img) in ONE tree: extract once, run all steps, then one label check,
# one mkfs.erofs per partition and one lpmake. Replaces the layer chain of build_port.sh
# (36 x extract + mkfs + lpmake, 13-23 GB per layer).
#
#   sudo sh port.sh <tag> <donor-img-dir> [--until <step>] [--keep-tree]
#   sh port.sh --check <tag> <donor-img-dir> [--until <step>]       preflight only, builds nothing
#
#   <tag>           base name of the run. Work dir: port-work/<tag>/{tree,img,report,orig}.
#                   Use a NEW tag (not one that build_port.sh used): the run deletes port-work/<tag>/.
#   <donor-img-dir> the donor's extracted images (system.img, system_ext.img, product.img, my_*.img),
#                   e.g. ~/Documents/pipa/donor/OPD2515_11.C.06/img
#   --until <step>  stop after this step (default: the last one, 3p; 3k needs PORT_ODM_C06=1 to do anything). Step names: see steps/.
#   --keep-tree     keep port-work/<tag>/tree after a good run (default: delete it, 13-23 GB).
#                   After a failed run the tree always stays.
#
# Environment (all optional):
#   PORT_OVERLAY_SRC  frozen beta4 files for PORT-EDITS.tsv (default COS17/port-overlay; md5 list
#                     maintainer/c06-vs-beta4/port-overlay.md5). The old full beta4 tree port-work/roundtrip/src also works.
#                     Set it to a frozen overlay folder when you have one. It needs system/ and system_ext/.
#   PORT_WITH_2U=1    also apply step 2u (SukiSU preload). The old chain does NOT have it in 3h.
#   PORT_ODM_C06=1    also apply the optional step 3k (OPPO interconnect stack in the odm from C.06; NOTES-3k-odm-c06.md).
#   PORT_FORCE=1      allow a tag whose work dir port.sh did not create (the old chain used it).
#   PIPA_ROOT, PIPA_OWNER   as in the old layer scripts.
#
# Steps are the files port/steps/NN-<step>-<name>.sh, run in the order of NN, each as its own
# `sh` process with `set -eu`. A failing step stops the run and keeps the tree.
set -eu

PORT=$(cd "$(dirname "$0")" && pwd)
HERE=$(cd "$PORT/.." && pwd)                   # COS17/maintainer

die() { echo "port.sh: $*" >&2; exit 1; }

CHECK=0; KEEP=0; UNTIL=""; TAG=""; DONOR_IMG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --keep-tree) KEEP=1 ;;
        --until) [ $# -ge 2 ] || die "--until needs a step name"; UNTIL=$2; shift ;;
        --until=*) UNTIL=${1#--until=} ;;
        -h|--help) sed -n '2,/^set -eu/p' "$0" | sed '$d'; exit 0 ;;
        -*) die "unknown option $1" ;;
        *) if [ -z "$TAG" ]; then TAG=$1; elif [ -z "$DONOR_IMG" ]; then DONOR_IMG=$1; else die "too many arguments"; fi ;;
    esac
    shift
done
[ -n "$TAG" ] && [ -n "$DONOR_IMG" ] || die "usage: sudo sh port.sh <tag> <donor-img-dir> [--until <step>] [--keep-tree]"
DONOR_IMG=$(cd "$DONOR_IMG" 2>/dev/null && pwd) || die "donor image dir not found: $DONOR_IMG"

PIPA_ROOT=${PIPA_ROOT:-/home/stefan/Documents/pipa}
P=$PIPA_ROOT/port-work
OWNER=${PIPA_OWNER:-stefan:stefan}
PORT_OVERLAY_SRC=${PORT_OVERLAY_SRC:-$HERE/../port-overlay}  # frozen beta4 files for PORT-EDITS.tsv (base step)
PARTS=$HERE/../work/parts                                   # beta4 vendor/odm images (slot B)
ROM=$HERE/../port-rom
MOD=$HERE/../module
TOOLS=$MOD/tools
W=$P/$TAG
T=$W/tree
R=$W/report
ORIG=$W/orig
STATE=$W/state
VENDOR_MD5=b601a907363d01e78697cd5d4f60edf6                 # work/parts/vendor_b.img
ODM_MD5=8e25ab23745ad3d9abb7a3312abe3e23                    # work/parts/odm_b.img
MY_MOUNTS="my_product my_manifest my_stock my_region my_heytap my_bigball my_carrier my_engineering"
PARTITIONS="system system_ext product vendor odm"
MKFS_FLAGS="-zlz4hc -C65536 -T0"                            # the flags of every old layer
export T W R ORIG HERE PORT ROM MOD TOOLS PARTS DONOR_IMG TAG OWNER P PIPA_ROOT PORT_OVERLAY_SRC

# ---- step list ----------------------------------------------------------------------------
step_id() { b=${1##*/}; b=${b#*-}; echo "${b%%-*}"; }
ALL=$(ls "$PORT"/steps/[0-9][0-9]-*.sh 2>/dev/null) || die "no steps in $PORT/steps"
SELECTED=""; found=0
[ -z "$UNTIL" ] && found=1 || :
for f in $ALL; do
    SELECTED="$SELECTED $f"
    [ -n "$UNTIL" ] && [ "$(step_id "$f")" = "$UNTIL" ] && { found=1; break; }
done
if [ "$found" != 1 ]; then
    echo "unknown step '$UNTIL'. Steps:" >&2; for f in $ALL; do printf ' %s' "$(step_id "$f")" >&2; done; echo >&2; exit 2
fi
LASTSTEP=$(step_id "$(echo $SELECTED | tr ' ' '\n' | tail -1)")
ids=$(for f in $ALL; do step_id "$f"; done | sort | uniq -d)
[ -z "$ids" ] || die "duplicate step names: $ids"

# ---- preflight ----------------------------------------------------------------------------
ok=1
say() { printf '%-36s %s\n' "$1" "$2"; }
need() { if [ -e "$2" ]; then say "$1" "ok"; else say "$1" "MISSING: $2"; ok=0; fi; }
free_gb() { df --output=avail -k "$P" | tail -1 | awk '{printf "%d", $1/1048576}'; }

echo "== preflight (tag $TAG, donor $DONOR_IMG, steps up to $LASTSTEP)"
if mountpoint -q /mnt/reference; then say "HDD /mnt/reference" ok; else say "HDD /mnt/reference" "NOT MOUNTED (work/parts, donor symlinks)"; ok=0; fi
for t in fsck.erofs mkfs.erofs dump.erofs lpmake python3 getfattr setfattr awk find df md5sum; do
    if command -v "$t" >/dev/null 2>&1; then :; else say "tool $t" "MISSING"; ok=0; fi
done
for img in system system_ext product $MY_MOUNTS; do need "donor $img.img" "$DONOR_IMG/$img.img"; done
need "port edit list" "$HERE/c06-vs-beta4/PORT-EDITS.tsv"
need "overlay source system/ (PORT_OVERLAY_SRC)" "$PORT_OVERLAY_SRC/system"
need "overlay source system_ext/" "$PORT_OVERLAY_SRC/system_ext"
need "vendor_b.img (pinned base)" "$PARTS/vendor_b.img"
need "odm_b.img (pinned base)" "$PARTS/odm_b.img"
if [ -f "$PARTS/vendor_b.img" ]; then
    have=$(md5sum < "$PARTS/vendor_b.img" | cut -c1-32)
    if [ "$have" = "$VENDOR_MD5" ]; then say "vendor_b.img md5" ok; else say "vendor_b.img md5" "$have, expected $VENDOR_MD5"; ok=0; fi
fi
if [ -f "$PARTS/odm_b.img" ]; then
    have=$(md5sum < "$PARTS/odm_b.img" | cut -c1-32)
    if [ "$have" = "$ODM_MD5" ]; then say "odm_b.img md5" ok; else say "odm_b.img md5" "$have, expected $ODM_MD5"; ok=0; fi
fi
# every step lists its own inputs in "#NEEDS:" lines (paths may use the exported variables)
for f in $SELECTED; do
    grep '^#NEEDS:' "$f" | sed 's/^#NEEDS:[[:space:]]*//' | while read -r line; do
        eval "set -- $line"
        for path in "$@"; do
            if [ -e "$path" ]; then :; else echo "MISSING input of $(basename "$f"): $path"; fi
        done
    done
done > "${TMPDIR:-/tmp}/port-needs.$$"
if [ -s "${TMPDIR:-/tmp}/port-needs.$$" ]; then cat "${TMPDIR:-/tmp}/port-needs.$$"; ok=0; else say "step inputs (#NEEDS)" ok; fi
rm -f "${TMPDIR:-/tmp}/port-needs.$$"
free=$(free_gb)
if [ "${free:-0}" -ge 40 ]; then say "free space on port-work" "${free} GB ok"; else say "free space on port-work" "${free} GB: 40 GB needed (tree 13-23 GB + images 7 GB + extract)"; ok=0; fi
if [ -e "$W" ] && [ ! -e "$W/.port-sh" ] && [ "${PORT_FORCE:-0}" != 1 ]; then
    say "work dir port-work/$TAG" "EXISTS and was not made by port.sh (PORT_FORCE=1 to overwrite)"; ok=0
elif [ -e "$P/$TAG-baked" ] && [ "${PORT_FORCE:-0}" != 1 ]; then
    say "tag $TAG" "used by the old chain ($TAG-baked exists): use a new tag or PORT_FORCE=1"; ok=0
fi
[ "$ok" = 1 ] || { echo "preflight failed"; exit 1; }
if [ "$CHECK" = 1 ]; then echo "preflight ok (nothing built)"; exit 0; fi
[ "$(id -u)" = 0 ] || die "run with sudo"

# ---- run ----------------------------------------------------------------------------------
rm -rf "$W/tree" "$W/orig" "$W/state" "$W/img" "$W/report" "$W/donor" "$W/scratch"
mkdir -p "$T" "$ORIG" "$STATE" "$W/img" "$R/steps"
: > "$W/.port-sh"
LOG=$R/port.log
log() { echo "$*"; echo "$*" >> "$LOG"; }
now() { date +%s; }
TIMING=""
note_time() { TIMING="$TIMING$(printf '%-34s %6d s' "$1" "$2")
"; }
trap 'chown -R "$OWNER" "$W/img" "$R" 2>/dev/null || :' EXIT
fail() { log "FAILED: $*"; log "tree kept: $T"; exit 1; }
space_check() {   # a full disk truncates super.img without an error
    free=$(free_gb)
    [ "${free:-0}" -ge 20 ] || fail "less than 20 GB free in $P ($free GB) before $1"
}

log "port.sh $TAG donor=$DONOR_IMG steps=..$LASTSTEP overlay=$PORT_OVERLAY_SRC started $(date '+%F %T')"
T0=$(now)

log "== extract donor (system, system_ext, my_* into system/), product; pinned vendor, odm"
t=$(now)
fsck.erofs --extract="$T/system" --xattrs --preserve "$DONOR_IMG/system.img" > "$R/extract_system.log" 2>&1 || fail "extract system.img"
fsck.erofs --extract="$T/system_ext" --xattrs --preserve "$DONOR_IMG/system_ext.img" > "$R/extract_system_ext.log" 2>&1 || fail "extract system_ext.img"
for m in $MY_MOUNTS; do
    [ -d "$T/system/$m" ] || fail "missing mount point /$m"
    rm -rf "$W/tmp_$m"
    fsck.erofs --extract="$W/tmp_$m" --xattrs --preserve "$DONOR_IMG/$m.img" > "$R/extract_$m.log" 2>&1 || fail "extract $m.img"
    # move the contents into the (labelled) mount point; the image's own root dir is dropped
    find "$W/tmp_$m" -mindepth 1 -maxdepth 1 -exec mv -t "$T/system/$m/" {} + || fail "move $m"
    rm -rf "$W/tmp_$m"
done
fsck.erofs --extract="$T/product" --xattrs --preserve "$DONOR_IMG/product.img" > "$R/extract_product.log" 2>&1 || fail "extract product.img"
fsck.erofs --extract="$T/vendor" --xattrs --preserve "$PARTS/vendor_b.img" > "$R/extract_vendor.log" 2>&1 || fail "extract vendor_b.img"
fsck.erofs --extract="$T/odm" --xattrs --preserve "$PARTS/odm_b.img" > "$R/extract_odm.log" 2>&1 || fail "extract odm_b.img"
for p in $PARTITIONS; do [ -d "$T/$p" ] || fail "no tree for $p"; done
. "$PORT/lib.sh"     # needs the tree: gives fingerprint() (lib.sh stops the run if a variable is unset)
# a baseline per partition: later we mkfs only partitions that a step changed (as the old chain did)
for p in $PARTITIONS; do fingerprint "$T/$p" > "$STATE/base.$p"; done
note_time "extract (donor + vendor + odm)" "$(( $(now) - t ))"
log "   extracted in $(( $(now) - t )) s"

for f in $SELECTED; do
    id=$(step_id "$f"); name=${f##*/}; name=${name%.sh}
    log "== step $name ($(date +%T))"
    t=$(now); rcf=$R/steps/.rc; rm -f "$rcf"
    { rc=0; PORT_STEP=$id sh "$f" </dev/null || rc=$?; echo "$rc" > "$rcf"; } 2>&1 | tee "$R/steps/$name.log"
    rc=$(cat "$rcf" 2>/dev/null || echo 99)
    if [ "$rc" != 0 ]; then
        note_time "step $name FAILED" "$(( $(now) - t ))"
        echo "$TIMING" > "$R/timing.txt"
        case "$id" in
            base|baked) echo "On a new donor this is the expected md5 safety stop: regenerate the fix from the new file, update the md5 in the step, and run again." ;;
        esac
        fail "step $name (exit $rc). Log: $R/steps/$name.log"
    fi
    note_time "step $name" "$(( $(now) - t ))"
    log "   $name done in $(( $(now) - t )) s"
done

# ---- which partitions did the steps change? -------------------------------------------------
# system and system_ext always get a new image (the base step edits them). The others stay a copy of
# their input image when no step touched them (as in the old chain, where a layer copied product.img,
# vendor.img and odm.img unchanged).
BUILD=""; COPY=""
for p in $PARTITIONS; do
    now_fp=$(fingerprint "$T/$p")
    case "$p" in
        system|system_ext) BUILD="$BUILD $p" ;;
        *) if [ "$now_fp" = "$(cat "$STATE/base.$p")" ]; then COPY="$COPY $p"; else BUILD="$BUILD $p"; fi ;;
    esac
done
log "== partitions: new image for$BUILD; unchanged input copied for${COPY:- (none)}"

log "== label check (one pass per partition)"
t=$(now)
for p in $BUILD; do
    python3 -I "$HERE/tree_manifest.py" "$T/$p" > "$R/$p.tsv" || fail "tree_manifest $p"
    n=$(awk -F'\t' '$7 !~ /security.selinux/' "$R/$p.tsv" | wc -l)
    log "$p: $(wc -l < "$R/$p.tsv") entries, $n without a SELinux label"
    if [ "$n" != 0 ]; then awk -F'\t' '$7 !~ /security.selinux/' "$R/$p.tsv" | head; fail "$p has entries without a SELinux label"; fi
done
note_time "label check" "$(( $(now) - t ))"

log "== mkfs.erofs $MKFS_FLAGS"
space_check mkfs
for p in $BUILD; do
    t=$(now)
    # shellcheck disable=SC2086
    mkfs.erofs $MKFS_FLAGS "$W/img/$p.img" "$T/$p" > "$R/mkfs_$p.log" 2>&1 || { tail -20 "$R/mkfs_$p.log"; fail "mkfs.erofs $p"; }
    [ -s "$W/img/$p.img" ] || fail "mkfs.erofs $p gave no image"
    note_time "mkfs $p" "$(( $(now) - t ))"
    log "   $p.img $(stat -c %s "$W/img/$p.img") bytes, $(( $(now) - t )) s"
done
for p in $COPY; do
    case "$p" in
        product) src=$DONOR_IMG/product.img ;;
        vendor) src=$PARTS/vendor_b.img ;;
        odm) src=$PARTS/odm_b.img ;;
        *) fail "no input image for unchanged $p" ;;
    esac
    cp --reflink=auto "$src" "$W/img/$p.img" || fail "copy $src"
done
ls -l "$W/img"

log "== super (lpmake)"
space_check lpmake
t=$(now)
cd "$W/img"
set --
for p in $PARTITIONS; do set -- "$@" --partition "${p}_a:readonly:0:qti_dynamic_partitions_a"; done
for p in $PARTITIONS; do
    set -- "$@" --partition "${p}_b:readonly:$(stat -c %s $p.img):qti_dynamic_partitions_b" --image "${p}_b=$p.img"
done
rm -f super.img
lpmake_rc=0
lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --virtual-ab \
    --device super:9126805504 \
    --group qti_dynamic_partitions_a:9126805504 --group qti_dynamic_partitions_b:9126805504 \
    "$@" --sparse --output super.img > "$R/lpmake.log" 2>&1 || lpmake_rc=$?
if [ "$lpmake_rc" != 0 ]; then cat "$R/lpmake.log"; rm -f super.img; fail "lpmake exit $lpmake_rc"; fi
[ -s super.img ] || fail "lpmake gave no super.img"
# only the two known harmless message kinds may be left out of the log; all else is shown
rest=$(grep -v -e 'will resize' -e 'Invalid sparse' "$R/lpmake.log" || :)
if [ -n "$rest" ]; then
    echo "$rest"
    if echo "$rest" | grep -q -i -e error -e fail -e 'no space'; then rm -f super.img; fail "lpmake reported an error"; fi
fi
# size check: the sparse super.img is the sum of the images plus a little metadata (68 KB in 3h)
sum=0; for p in $PARTITIONS; do sum=$(( sum + $(stat -c %s "$p.img") )); done
size=$(stat -c %s super.img)
if [ "$size" -lt "$sum" ] || [ "$size" -gt $(( sum + 1048576 )) ]; then
    fail "super.img is $size bytes, expected $sum + <1 MiB (disk full? lpmake error?). Do not flash it."
fi
note_time "lpmake" "$(( $(now) - t ))"
MD5=$(md5sum super.img | cut -d' ' -f1)
log "   super.img $size bytes (images $sum + $(( size - sum )))"
log "   md5 $MD5"

# ---- report ---------------------------------------------------------------------------------
note_time "TOTAL" "$(( $(now) - T0 ))"
REPORT=$R/PORT-REPORT.txt
{
    echo "port.sh report  $(date '+%F %T')"
    echo "tag            $TAG"
    echo "donor          $DONOR_IMG"
    echo "last step      $LASTSTEP"
    echo "overlay src    $PORT_OVERLAY_SRC"
    echo "PORT-EDITS.tsv $(md5sum < "$HERE/c06-vs-beta4/PORT-EDITS.tsv" | cut -c1-32)"
    echo "new images     $BUILD"
    echo "copied images  ${COPY:- (none)}"
    echo
    echo "timing:"
    printf '%s' "$TIMING"
    echo
    echo "image md5 (the UUID inside each EROFS image is random: image md5s change on every run;"
    echo "compare file contents with tree_manifest.py output in this folder, not image md5s):"
    for p in $PARTITIONS; do printf '  %-11s %12d  %s\n' "$p.img" "$(stat -c %s "$p.img")" "$(md5sum < "$p.img" | cut -c1-32)"; done
    echo
    echo "super.img      $W/img/super.img"
    echo "size           $size"
    echo "md5            $MD5"
} > "$REPORT"
cat "$REPORT"

cd "$W"
if [ "$KEEP" = 1 ]; then
    log "tree kept (--keep-tree): $T"
else
    log "removing the tree (use --keep-tree to keep it)"
    rm -rf "$T" "$ORIG" "$STATE" "$W/scratch" "$W/donor"
fi
echo
echo "== done: $W/img/super.img"
echo "md5 $MD5"
echo "dirty flash : sh $HERE/flash_super.sh -y $W/img/super.img $MD5   (add a name to flash_super.sh first)"
echo "then        : sh $HERE/device_check.sh $TAG"
echo "report      : $REPORT"
echo
echo "== re-verify on a new donor (nothing checks these automatically)"
cat <<'EOF2'
 - before the build: sudo bash maintainer/donor_check.sh <old-donor-img> <new-donor-img> (boot hangs, md5 gates)
 - boot: no hang in system_server, adb authenticated (ro.adb.secure=1)
 - rotation and boot logo, face unlock + enrollment, pen buttons/pill/120 Hz lock, Dolby after reboot,
   magnetic case, charger info, interconnect (network, calls), Game Filter, YouTube HDR
 - SELinux: logcat 'avc:.*pipa_port' after boot (pipa_port is enforcing)
EOF2
