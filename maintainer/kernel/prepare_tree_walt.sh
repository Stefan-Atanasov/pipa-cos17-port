#!/bin/bash
# Recreate our own WALT kernel tree from upstream + our commits (saved as a git bundle in COS17/kernel/).
#   bash maintainer/kernel/prepare_tree_walt.sh [out-dir]      default port-work/kernel/walt-own
#   then: TREE=<out-dir> bash maintainer/kernel/build_walt.sh, mkboot.sh, flash_kernel.sh test
# Branches restored: own (Lineage 24 + liyafe pipa + our fixes + SukiSU/susfs), oppo (own + OPPO sched_assist; worktree
# <out-dir>/../walt-oppo). Update the bundle after committing: `bash maintainer/kernel/prepare_tree_walt.sh --save`.
# Updating upstream later: `git fetch lineage && git merge lineage/lineage-24.0` on own (same rules as the first merge:
# core = Lineage, device drivers = ours), then merge own into oppo. Details: kernel/WALT-KERNEL.md.
set -euo pipefail
K=${K:-${PIPA_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/port-work/kernel}
C=$(cd "$(dirname "$0")/../.." && pwd)            # COS17
B=$C/kernel/walt-own.bundle
LINEAGE=https://github.com/LineageOS/android_kernel_xiaomi_sm8250
LIYAFE=https://github.com/liyafe1997/kernel_xiaomi_sm8250_mod

if [ "${1:-}" = --save ]; then
	T=${2:-$K/walt-own}
	# only our objects: everything reachable from own/oppo but not from the upstream branches
	git -C "$T" bundle create "$B.new" own oppo ksu ^lineage/lineage-24.0 ^liyafe/android15-lineage22-mod
	git bundle verify "$B.new" >/dev/null 2>&1 || git -C "$T" bundle verify "$B.new"
	mv "$B.new" "$B"; ls -la "$B"; exit 0
fi

OUT=${1:-$K/walt-own}
[ -e "$OUT" ] && { echo "$OUT exists" >&2; exit 1; }
[ -f "$B" ] || { echo "missing $B" >&2; exit 1; }
git init -q "$OUT"
cd "$OUT"
git remote add lineage "$LINEAGE"; git config remote.lineage.partialclonefilter blob:none
git remote add liyafe "$LIYAFE"; git config remote.liyafe.partialclonefilter blob:none
git config remote.lineage.promisor true; git config remote.liyafe.promisor true
git fetch -q --filter=blob:none lineage lineage-24.0
git fetch -q --filter=blob:none liyafe android15-lineage22-mod
git fetch -q "$B" 'refs/heads/*:refs/heads/*'
git checkout -q own
git worktree add -q ../walt-oppo oppo
git log --oneline -3 own | cat
echo "tree ready: $OUT (branch own), ../walt-oppo (branch oppo)"
