#!/bin/bash
# Recreate the pipa COS17 kernel tree from upstream + our two patches, e.g. for a new E404 or SukiSU commit.
#   bash maintainer/kernel/prepare_tree.sh <out-tree> [E404_REF] [SUKISU_REF]
#   defaults: E404 staging-bpf 9b8e5a79, SukiSU builtin 7f1c299a (the tested pair)
# Then: TREE=<out-tree> bash maintainer/kernel/build_kernel.sh; bash maintainer/kernel/mkboot.sh ...; flash_kernel.sh test.
#
# e404-pipa.patch  = susfs 2.3.0 + its inline hooks (JackA1ltman 4.19 port, extern types fixed for SukiSU builtin)
#                    + ramoops_memreserve (pstore on pipa) + kernel/sched/uclamp_boost.c (touch boost for CASS: top-app and
#                    foreground uclamp.min 40 % while touching, /sys/module/uclamp_boost/parameters/{pct,ms}).
#                    Regenerate from a finished tree with `git add -N fs/susfs.c include/linux/susfs*.h
#                    kernel/sched/uclamp_boost.c; git diff HEAD -- . ':!.gitmodules' ':!KernelSU'`.
# sukisu-pipa.patch = 4.19 build fixes + version pin (kernel/Makefile: LOCAL_COUNT/KSU_VERSION_FULL; update both
#                    when moving to another SukiSU commit, else the manager shows a wrong version).
# On a new E404 commit `git apply -3` leaves conflict markers instead of failing; fix them, rebuild, test-boot.
# After a SukiSU update, compare every `extern` in the hooks (fs/exec.c, open.c, stat.c, read_write.c,
# drivers/input/input.c) with SukiSU's definitions: a static_key/bool mismatch links fine and corrupts memory.
set -euo pipefail
OUT=${1:?usage: prepare_tree.sh <out-tree> [E404_REF] [SUKISU_REF]}
E404_REF=${2:-9b8e5a79}
SUKISU_REF=${3:-7f1c299a}
K=${K:-$HOME/Documents/pipa/port-work/kernel}
P=$(cd "$(dirname "$0")" && pwd)
E404_GIT=${E404_GIT:-$K/e404-stbpf}          # clone of kvsnr113/xiaomi_sm8250_kernel_e404
SUKI_GIT=${SUKI_GIT:-$K/sukisu-7f1c}         # clone of SukiSU-Ultra/SukiSU-Ultra (branch builtin)
[ -e "$OUT" ] && { echo "$OUT exists" >&2; exit 1; }

git -C "$E404_GIT" fetch -q origin || echo "warning: E404 fetch failed, using local objects" >&2
git -C "$SUKI_GIT" fetch -q origin || echo "warning: SukiSU fetch failed, using local objects" >&2
git clone -q --no-checkout "$E404_GIT" "$OUT"
git -C "$OUT" checkout -q "$(git -C "$E404_GIT" rev-parse "$E404_REF^{commit}")"
git -C "$OUT" rm -q --cached KernelSU 2>/dev/null || true
rm -f "$OUT/.gitmodules"; rm -rf "$OUT/KernelSU"; mkdir "$OUT/KernelSU"
git -C "$SUKI_GIT" archive "$SUKISU_REF" kernel LICENSE | tar -x -C "$OUT/KernelSU"
ln -s ./kernel/include/uapi "$OUT/KernelSU/uapi"
[ -L "$OUT/drivers/kernelsu" ] || ln -s ../KernelSU/kernel "$OUT/drivers/kernelsu"

(cd "$OUT/KernelSU" && patch -p1 --no-backup-if-mismatch < "$P/sukisu-pipa.patch")
git -C "$OUT" apply -3 --whitespace=nowarn "$P/e404-pipa.patch" || {
	echo "e404-pipa.patch did not apply cleanly: resolve the conflicts in $OUT (git -C $OUT diff --name-only --diff-filter=U)" >&2
	exit 2; }
echo "tree ready: $OUT (E404 $E404_REF, SukiSU $SUKISU_REF)"
