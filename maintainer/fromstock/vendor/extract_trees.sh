#!/bin/sh
# extract_trees.sh: (re)create the trees the scripts default to (x/b4v x/b4o x/c06v x/c06o), as the normal user, no labels.
# For a REAL image build extract PixelOS vendor as root with: fsck.erofs --extract=DIR --xattrs --preserve IMG
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); P=${PIPA_ROOT:-$HOME/Documents/pipa}
X=${X:-$P/port-work/fromstock/x}   # the same default as make_from_stock.sh (C06V, C06O)
mkdir -p "$X"
fsck.erofs --extract="$X/b4v" --no-preserve $P/COS17/work/parts/vendor_b.img
fsck.erofs --extract="$X/b4o" --no-preserve $P/COS17/work/parts/odm_b.img
fsck.erofs --extract="$X/c06v" --no-preserve $P/port-work/donor-c06-vendor/vendor.img
fsck.erofs --extract="$X/c06o" --no-preserve $P/port-work/donor-c06-vendor/odm.img
