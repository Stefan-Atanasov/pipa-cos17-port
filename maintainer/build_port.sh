#!/bin/sh
# Build the whole port (ROM image) from a donor build, all steps in order, under one base name.
#
#   sudo sh build_port.sh <tag> <donor-img-dir> [first-step] [last-step]
#   sh build_port.sh --check <tag> <donor-img-dir>        preflight only, builds nothing
#
#   <tag>           base name: work dirs become port-work/<tag>, <tag>-baked, <tag>-1c ... <tag>-2h
#                   (beta5 = the current C.06 build; use a new tag like beta6 for a new donor)
#   <donor-img-dir> the donor's extracted images (system.img, system_ext.img, product.img, my_*.img ...),
#                   e.g. ~/Documents/pipa/donor/OPD2515_11.C.06/img
#   first/last-step one of: base baked 1c 2a 2b 2c 2d 2e 2f 2g 2h  (default: all; use it to resume)
#
# Steps (each is maintainer/build_beta5[_<step>].sh with TAG and DONOR_IMG set):
#   base   rebase: donor system/system_ext/product + the curated port edits (c06-vs-beta4/PORT-EDITS.tsv)
#   baked  vendor/system files the old module bound (QDCM colour, audio curves, brightness table, patched jar)
#   1c     GNSS service off, pen sysfs permissions      2a  FaceUnlock app + AOD removed
#   2b     keyboard drain patch + pen sysfs rc          2c  interconnect rule + native pen 120 Hz lock
#   2d     pipa helper app (first form)                 2e  pipa_port runtime + boot rotation/logo + helper 0.4
#   2f     pen button / pen message fixes               2g  AudioX retry loop disabled by sysconfig
#   2h     gpuservice extension null guards (own kernel) 2i  UI First SELinux (own kernel, branch oppo)
#   2j     keyboard guard (idle drain), loc_sys_service disabled, SF props, no vsock traced relay
#   2k     charger shim: battery reported genuine (no "battery may not be genuine" dialog)
#   2l     smoothness: SurfaceFlinger off the little cores (UI First scene), SF early offsets in product build.prop
#   2m     SF layer caching off again (screen glitches in Settings search)
#   2n     system_server animation threads as UX, UI apps fully compiled (QS -> Settings launch)
#
# On a NEW donor the first two steps are EXPECTED to stop: they check the stock md5 of every file they
# replace (oplus-services.jar, brightness xml, odm scripts ...). That is the safety net. When one stops, read
# the message, regenerate the fix from the new donor's file (module/tools/*, patch_framework.sh), update the
# md5 in the script, and resume with the first-step argument. Before a new donor also do:
#   * maintainer/wfs_scan.sh <old tree> <new tree>   new waitForService imports hang system_server on boot
#   * maintainer/port_diff.py                        new C.0x-vs-old diff -> update c06-vs-beta4/PORT-EDITS.tsv
#   * PORT-MAINTAINER.md                             rebase procedure and regression checklist
# After the build: sh flash_super.sh <path-to-super.img> <md5> (dirty flash), then maintainer/device_check.sh <tag>.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
STEPS="base baked 1c 2a 2b 2c 2d 2e 2f 2g 2h 2i 2j 2k 2l 2m 2n"

CHECK=0
[ "${1:-}" = "--check" ] && { CHECK=1; shift; }
TAG=${1:?usage: sudo sh build_port.sh <tag> <donor-img-dir> [first-step] [last-step]}
DONOR_IMG=${2:?donor image dir missing}
FIRST=${3:-base}
LAST=${4:-2h}

script_of() { [ "$1" = base ] && echo "$HERE/build_beta5.sh" || echo "$HERE/build_beta5_$1.sh"; }
dir_of()    { [ "$1" = base ] && echo "$P/$TAG" || echo "$P/$TAG-$1"; }
valid() { for s in $STEPS; do [ "$s" = "$1" ] && return 0; done; return 1; }
valid "$FIRST" && valid "$LAST" || { echo "steps: $STEPS"; exit 2; }

ok=1
say() { printf '%-34s %s\n' "$1" "$2"; }
need() { if [ -e "$2" ]; then say "$1" "ok"; else say "$1" "MISSING: $2"; ok=0; fi; }

echo "== preflight (tag $TAG, donor $DONOR_IMG, steps $FIRST..$LAST)"
mountpoint -q /mnt/reference && say "HDD /mnt/reference" ok || { say "HDD /mnt/reference" "NOT MOUNTED (work/parts, donor symlinks)"; ok=0; }
need "donor system.img" "$DONOR_IMG/system.img"
need "donor system_ext.img" "$DONOR_IMG/system_ext.img"
need "donor product.img" "$DONOR_IMG/product.img"
need "port edit list" "$HERE/c06-vs-beta4/PORT-EDITS.tsv"
need "beta4 build inputs (work/parts)" "$HERE/../work/parts/vendor_b.img"
need "pipa helper APK" "$HERE/../helper/out/PipaHelper.apk"
need "face crop add-on" "$HERE/../port-rom/pipa_port/facehal/lib64/libpipa_facecrop.so"
need "boot logo zips" "$HERE/bootanim/bootanimation.zip"
for s in $STEPS; do need "script $s" "$(script_of "$s")"; done
free=$(df --output=avail -BG "$P" | tail -1 | tr -dc 0-9)
if [ "${free:-0}" -ge 60 ]; then say "free space on port-work" "${free} GB ok"; else say "free space on port-work" "${free} GB: each step adds ~7 GB image + reflinked trees, 60+ GB advised"; ok=0; fi
[ -e "$P/$TAG" ] && [ "$FIRST" = base ] && say "existing $TAG work dirs" "will be overwritten by their steps"
# a resumed run needs the previous step's tree
if [ "$FIRST" != base ]; then
    prev=""; for s in $STEPS; do [ "$s" = "$FIRST" ] && break; prev=$s; done
    need "previous step output ($prev)" "$(dir_of "$prev")/img/super.img"
fi
[ "$ok" = 1 ] || { echo "preflight failed"; exit 1; }
[ "$CHECK" = 1 ] && { echo "preflight ok (nothing built)"; exit 0; }
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

REPORT=$P/$TAG-BUILD-REPORT.txt
echo "build_port.sh $TAG donor=$DONOR_IMG steps=$FIRST..$LAST started $(date '+%F %T')" >> "$REPORT"
run=0
for s in $STEPS; do
    [ "$s" = "$FIRST" ] && run=1
    [ "$run" = 1 ] || continue
    echo "== step $s ($(date +%T))"
    t0=$(date +%s)
    if ! TAG=$TAG DONOR_IMG=$DONOR_IMG sh "$(script_of "$s")"; then
        echo "STEP $s FAILED. Log: $(dir_of "$s")/report/build.log (or the script output above)."
        case "$s" in base|baked)
            echo "On a new donor this is the expected md5 safety stop: regenerate the fix from the new file, update the md5, resume with: sudo sh build_port.sh $TAG $DONOR_IMG $s";;
        esac
        echo "step $s FAILED $(date '+%F %T')" >> "$REPORT"
        exit 1
    fi
    img=$(dir_of "$s")/img/super.img
    [ -f "$img" ] || { echo "step $s produced no super.img ($img)"; exit 1; }
    md5=$(md5sum "$img" | cut -d' ' -f1)
    echo "   $s done in $(( $(date +%s) - t0 )) s: $img $md5"
    echo "step $s ok $md5" >> "$REPORT"
    [ "$s" = "$LAST" ] && break
done

echo
echo "== done: $img"
echo "md5 $md5"
echo "dirty flash : sh $HERE/flash_super.sh -y $img $md5"
echo "then        : sh $HERE/device_check.sh $TAG"
echo "report      : $REPORT"
echo
echo "== re-verify on a new base (these depend on the donor, nothing checks them automatically)"
cat <<'EOF'
 - boot: no hang in system_server (wfs_scan.sh result), adb authenticated (ro.adb.secure=1)
 - ColorOS rotation/boot: first rotation landscape, boot logo centred (bootanimation desc.txt offset,
   ro.panel.pad_orientation)
 - face unlock + enrollment preview (rotation sync, square crop), pen buttons/pill/120 Hz lock, Dolby after reboot,
   magnetic case switch, charger info, interconnect daemons
 - the AudioX retry loop (logcat 'Failed to recreate AudioxEffect' every 3 s)
 - SELinux: avc_trace.sh dump after boot, new denials of the pipa_port domain
EOF
