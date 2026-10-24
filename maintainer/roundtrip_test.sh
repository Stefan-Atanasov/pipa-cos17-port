#!/bin/sh
# Round-trip test of the rebuild pipeline on unchanged beta4 content (PORT-MAINTAINER.md step 2).
# extract system/system_ext as root with xattrs -> mkfs.erofs -> re-extract -> compare every
# path, type, mode, owner, content hash, symlink target and xattr (SELinux label, capabilities).
# Read-only on COS17/work/parts; writes only under $W. Run: sudo sh roundtrip_test.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
PARTS="$HERE/../work/parts"
W=${PIPA_ROOT:-/home/stefan/Documents/pipa}/port-work/roundtrip
OWNER=${PIPA_OWNER:-stefan:stefan}
mkdir -p "$W/src" "$W/img" "$W/chk" "$W/report"

for p in system system_ext; do
    echo "== $p: extract original"
    rm -rf "$W/src/$p"
    fsck.erofs --extract="$W/src/$p" --xattrs --preserve "$PARTS/${p}_b.img"

    echo "== $p: rebuild"
    rm -f "$W/img/$p.img"
    mkfs.erofs -zlz4hc -C65536 -T0 "$W/img/$p.img" "$W/src/$p" > "$W/report/mkfs_$p.log" 2>&1

    echo "== $p: re-extract rebuilt image"
    rm -rf "$W/chk/$p"
    fsck.erofs --extract="$W/chk/$p" --xattrs --preserve "$W/img/$p.img"

    echo "== $p: compare"
    python3 -I "$HERE/tree_manifest.py" "$W/src/$p" > "$W/report/$p.orig.tsv"
    python3 -I "$HERE/tree_manifest.py" "$W/chk/$p" > "$W/report/$p.rebuilt.tsv"
    if diff -q "$W/report/$p.orig.tsv" "$W/report/$p.rebuilt.tsv" > /dev/null; then
        echo "$p: IDENTICAL ($(wc -l < "$W/report/$p.orig.tsv") entries)" | tee -a "$W/report/result.txt"
    else
        diff "$W/report/$p.orig.tsv" "$W/report/$p.rebuilt.tsv" > "$W/report/$p.diff" || true
        echo "$p: DIFFERENT, see report/$p.diff ($(grep -c '^[<>]' "$W/report/$p.diff") lines)" | tee -a "$W/report/result.txt"
    fi
    {
        echo "== $p original";  dump.erofs -s "$PARTS/${p}_b.img" | grep -E 'features|compr_algs|blocksize'
        echo "== $p rebuilt";   dump.erofs -s "$W/img/$p.img"     | grep -E 'features|compr_algs|blocksize'
        echo "size original $(stat -c %s "$PARTS/${p}_b.img") rebuilt $(stat -c %s "$W/img/$p.img")"
    } >> "$W/report/features.txt"
    rm -rf "$W/chk/$p"     # 10 GB; the manifest is enough
done

chown -R "$OWNER" "$W/img" "$W/report"
echo "done: $W/report/result.txt"
