#!/bin/sh
# Phase 2o: 120 Hz for apps in ColorOS's Auto refresh mode, on top of 2n (system only). Run as root:
#
#   sudo sh build_beta5_2o.sh
#
# system/my_product/etc/refresh_rate_config.xml caps many apps in Auto mode (rateId "auto-90-60-120", values
# 1 = 90 Hz, 2 = 60 Hz, 3 = 120 Hz): music apps at 60 Hz, others at 60/90. With an animation boost Spotify ran at 90 Hz
# and the panel switched 90 <-> 120 in the middle of every open/close animation (stutter; 2026-10-24 trace: SF frames
# on time 83 % -> 90 % with Spotify at 120). This step sets field 1 (Auto) and field 4 (120 Hz mode) of every
# app-wide rule to 3 (120 Hz). Per-activity rules (video players, live streams), CTS entries and the 90/60 Hz setting
# modes stay as OPPO set them; other fullscreen video drops through Android's content detection.
#
# Input: port-work/${TAG}-2n/tree/{system,system_ext,product}, port-work/${TAG}-2n/img. Output: port-work/${TAG}-2o/.
set -eu
TAG=${TAG:-beta5}
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
P=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work
IMGSRC=$P/${TAG}-2n/img
W=$P/${TAG}-2o
HERE=$(cd "$(dirname "$0")" && pwd)
OWNER=${PIPA_OWNER:-stefan:stefan}
[ -f "$IMGSRC/super.img" ] || { echo "run build_beta5_2n.sh first"; exit 1; }

rm -rf "$W/tree"; mkdir -p "$W/tree" "$W/img" "$W/report"
exec > "$W/report/build.log" 2>&1
cp -a --reflink=auto "$P/${TAG}-2n/tree/system" "$P/${TAG}-2n/tree/system_ext" "$P/${TAG}-2n/tree/product" "$W/tree/"

echo "== refresh_rate_config: app-wide rules -> 120 Hz in Auto and 120 Hz modes"
python3 -I - "$W/tree/system/my_product/etc/refresh_rate_config.xml" "$W/report/refresh_rate_changes.txt" <<'PY'
import re, sys
path, rep = sys.argv[1:]
s = open(path, encoding='utf-8', errors='surrogateescape').read()
changed = []
def fix(m):
    line = m.group(0)
    if 'activity=' in line or '.cts' in line:
        return line
    def rid(r):
        f = r.group(1).split('-')
        if len(f) < 4:
            return r.group(0)
        old = '-'.join(f)
        f[0] = '3'; f[3] = '3'
        new = '-'.join(f)
        if new != old:
            changed.append(f"{re.search(r'package=\"([^\"]+)\"', line).group(1)} {old} -> {new}")
        return f'rateId="{new}"'
    return re.sub(r'rateId="([0-9-]+)"', rid, line)
s2 = re.sub(r'^\s*<item package="[^"]+"[^\n]*$', fix, s, flags=re.M)
if not changed:
    sys.exit("no rule changed: format changed?")
with open(path, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s2); f.truncate()
open(rep, 'w').write('\n'.join(changed) + '\n')
print(f"{len(changed)} app rules changed")
PY
grep -q 'package="com.spotify.music" rateId="3-' "$W/tree/system/my_product/etc/refresh_rate_config.xml"

echo "== label check"
python3 -I "$HERE/tree_manifest.py" "$W/tree/system" > "$W/report/system.tsv"
n=$(awk -F'\t' '$7 !~ /security.selinux/' "$W/report/system.tsv" | wc -l)
echo "system: $(wc -l < "$W/report/system.tsv") entries, $n without a SELinux label"
[ "$n" = 0 ] || exit 1

echo "== mkfs (system)"
mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/system.img" "$W/tree/system" > "$W/report/mkfs_system.log" 2>&1
for p in system_ext product vendor odm; do cp --reflink=auto "$IMGSRC/$p.img" "$W/img/$p.img"; done
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
