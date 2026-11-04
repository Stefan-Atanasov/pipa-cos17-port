#!/bin/sh
# Phase 5d: PC Screen Extend / PC Screen Mirror (OPPO PC Connect) show a picture, not black (BUGS-TODO 66; system_ext).
#
# The OPPO RTC decoder (com.oplus.ortc.AndroidVideoDecoder in odmf.jar) sets color-format 19 also when it decodes to a
# Surface; pipa's c2@1.0 decoder then makes CPU-only buffers that neither the composer nor the GPU can show.
# maintainer/odmf/patch_odmf_pcextend.sh skips that key in surface mode. Tested live 2026-11-04 (bind mount): both
# modes work.
# odmf.jar is not a plain file in the ROM: it is in system_ext/opex/odmf.opex (OPPO "opex" package: signed zip with an
# ext4 opex.img and its sha256 in description.cfg). init (handle_opex_package) loop-mounts it at
# /mnt/opex/com.oplus.odmf@<ver> and puts an overlay on /system_ext/framework/oplusex/com.oplus.odmf. We cannot change
# the signed package. So:
# * system_ext/pipa_port/odmf/{odmf.jar,odmf.txt}: the patched jar (from the opex image) and the empty marker file.
# * system_ext/etc/init/pipa_port.rc: on oplus.opex.done=1, init bind-mounts that folder over the overlay folder
#   (init may mount on system_file dirs, not on files). The libs (lib64 overlay) and the opex stay as they are.
# * system_ext/etc/build.prop: ro.pipa.port.layer=5d (changed jar: early.sh clears the package cache).
set -eu
. "$PORT/lib.sh"
STEP=5d
#NEEDS: "$HERE/odmf/patch_odmf_pcextend.sh" "$PIPA_ROOT/tools/smali/baksmali-2.5.2.jar"

OPEX=$T/system_ext/opex/odmf.opex
RC=$T/system_ext/etc/init/pipa_port.rc
DST=$T/system_ext/pipa_port/odmf
[ -f "$OPEX" ] || die "no $OPEX"
[ -d "$T/system_ext/framework/oplusex/com.oplus.odmf" ] || die "no overlay folder com.oplus.odmf in system_ext"
forbid_grep 'com.oplus.odmf' "$RC"
command -v debugfs >/dev/null || die "debugfs (e2fsprogs) missing"

echo "== odmf: jar from the opex image"
W=$R/odmf; rm -rf "$W"; mkdir -p "$W/ex"
unzip -q -o "$OPEX" opex.img description.cfg -d "$W"
H=$(sha256sum "$W/opex.img" | cut -c1-64)
grep -q "\"imgHash\": \"$H\"" "$W/description.cfg" || die "opex.img hash does not agree with description.cfg"
debugfs -R "dump /javalib/odmf.jar $W/odmf.jar" "$W/opex.img" >/dev/null 2>&1
[ -s "$W/odmf.jar" ] || die "odmf.jar not in opex.img"
md5sum "$W/odmf.jar"   # C.07 (opex 17001003): 383fcacc5c37d69355aa5525f5f8dc00

echo "== odmf: no color-format in surface decode mode"
ANDROID_HOME=${ANDROID_HOME:-/home/${OWNER%%:*}/Android/Sdk} bash "$HERE/odmf/patch_odmf_pcextend.sh" "$W/odmf.jar" "$W/odmf.jar.new"
install -d -o 0 -g 0 -m 755 "$DST"
install -o 0 -g 0 -m 644 "$W/odmf.jar.new" "$DST/odmf.jar"
install -o 0 -g 0 -m 644 /dev/null "$DST/odmf.txt"
for f in "$DST" "$DST/odmf.jar" "$DST/odmf.txt"; do setfattr -n security.selinux -v u:object_r:system_file:s0 "$f"; done
md5sum "$DST/odmf.jar"   # C.07: 8ae75020f20b883cfa073255fdf3485e
rm -rf "$W"

echo "== pipa_port.rc: bind the patched odmf folder after the opex mount"
{ cat "$RC"; printf '%s\n' '' \
  '# pipa port 5d (BUGS 66): patched odmf.jar (PC Screen Extend/Mirror) over the odmf opex overlay folder' \
  'on property:oplus.opex.done=1' \
  '    mount none /system_ext/pipa_port/odmf /system_ext/framework/oplusex/com.oplus.odmf bind'; } > "$R/pipa_port.rc.new"
cat "$R/pipa_port.rc.new" > "$RC"   # same inode
rm -f "$R/pipa_port.rc.new"
need_grep '^    mount none /system_ext/pipa_port/odmf /system_ext/framework/oplusex/com.oplus.odmf bind$' "$RC"

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
