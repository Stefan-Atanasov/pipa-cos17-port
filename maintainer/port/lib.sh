# Helpers for the port steps (sourced, not run):   . "$PORT/lib.sh"
#
# port.sh exports these variables before it runs a step:
#   T     tree root: $T/system $T/system_ext $T/product $T/vendor $T/odm
#   W     work dir of this run (port-work/<tag>); $T is $W/tree
#   R     report dir ($W/report): scratch output of the steps ends up here
#   ORIG  $W/orig: copies of files that a later step needs in their old state
#   HERE  COS17/maintainer      PORT  COS17/maintainer/port
#   ROM   COS17/port-rom        MOD   COS17/module        TOOLS  COS17/module/tools
#   PARTS COS17/work/parts      DONOR_IMG  donor image dir      TAG  base name of the run
#   OWNER user:group of the result files      P  port-work dir      PORT_OVERLAY_SRC  beta4 source tree
# A step sets its own STEP (its name, e.g. STEP=2q).
#
# Rules for steps (POSIX sh, set -eu):
#  * Write into an existing file with `cat new > old`, never `sed -i` or `mv`: the same inode keeps
#    the SELinux label, the owner and the mode.
#  * `set -e` ignores a negated command: `! grep -q x f` checks nothing. Use forbid_grep or
#    `if grep -q x f; then ...; exit 1; fi`.
#  * A failing check must stop the step with a message (die).

for _v in T W R ORIG HERE PORT ROM MOD TOOLS PARTS DONOR_IMG TAG OWNER P; do
    eval "[ -n \"\${$_v:-}\" ]" || { echo "lib.sh: \$$_v is not set (run the step through port.sh)" >&2; exit 1; }
done
unset _v
[ -d "$T/system" ] && [ -d "$T/system_ext" ] || { echo "lib.sh: no tree in $T" >&2; exit 1; }

die() { echo "FAIL: $*" >&2; exit 1; }

# need_grep <pattern> <file>: the pattern (basic regex) must occur
need_grep() { grep -q -- "$1" "$2" || die "$2: pattern not found: $1"; }
# forbid_grep <pattern> <file>: the pattern must not occur (a plain `! grep` is a no-op under set -e)
forbid_grep() { if grep -q -- "$1" "$2"; then die "$2: forbidden pattern present: $1"; fi; }

# replace_once <file> <old> <new>: exact text edit, <old> must occur exactly once, same inode.
# <file> is relative to $T or absolute. \n and \t in <old> and <new> are decoded (unicode_escape).
replace_once() {
    case "$1" in /*) _rf=$1 ;; *) _rf=$T/$1 ;; esac
    python3 -I - "$_rf" "$2" "$3" <<'PY' || die "replace_once: $1"
import sys
p, old, new = sys.argv[1:]
old, new = old.encode().decode('unicode_escape'), new.encode().decode('unicode_escape')
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != 1:
    sys.exit(f"{p}: anchor found {n} times, expected 1")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:   # same inode: label kept
    f.write(s.replace(old, new)); f.truncate()
PY
    echo "edited  ${1#$T/}"
}

# replace_all <file> <old> <new> <count>: like replace_once, but exactly <count> matches
replace_all() {
    case "$1" in /*) _rf=$1 ;; *) _rf=$T/$1 ;; esac
    python3 -I - "$_rf" "$2" "$3" "$4" <<'PY' || die "replace_all: $1"
import sys
p, old, new, cnt = sys.argv[1:]
s = open(p, encoding='utf-8', errors='surrogateescape').read()
n = s.count(old)
if n != int(cnt):
    sys.exit(f"{p}: anchor found {n} times, expected {cnt}")
with open(p, 'r+', encoding='utf-8', errors='surrogateescape') as f:
    f.write(s.replace(old, new)); f.truncate()
PY
    echo "edited  ${1#$T/} ($4x)"
}

# set_layer <name>: ro.pipa.port.layer=<name> in system_ext/etc/build.prop (early.sh clears the package
# cache when it changes). Replaces the line, or appends it when it is absent (first time: 2q).
set_layer() {
    _bp=$T/system_ext/etc/build.prop
    if grep -q '^ro.pipa.port.layer=' "$_bp"; then
        sed "s/^ro.pipa.port.layer=.*/ro.pipa.port.layer=$1/" "$_bp" > "$R/build.prop.new"
    else
        { cat "$_bp"; printf '\n# pipa port ROM layer (early.sh clears the package cache when it changes)\nro.pipa.port.layer=%s\n' "$1"; } > "$R/build.prop.new"
    fi
    cat "$R/build.prop.new" > "$_bp"        # same inode: label, owner and mode kept
    grep "^ro.pipa.port.layer=$1\$" "$_bp" || die "ro.pipa.port.layer=$1 not in $_bp"
}

# fingerprint <dir>: one md5 over path, type, size, mtime, owner, mode and link target of all entries.
# It reads no file content (fast). Any write to a file or directory changes it (the mtime).
fingerprint() {
    find "$1" -printf '%P\t%y\t%s\t%T@\t%U:%G\t%m\t%l\n' | LC_ALL=C sort | md5sum | cut -d' ' -f1
}
