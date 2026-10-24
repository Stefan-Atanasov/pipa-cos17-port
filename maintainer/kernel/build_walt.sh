#!/bin/bash
# Build our own WALT kernel: Lineage lineage-24.0 + liyafe's pipa port + our commits (tree: port-work/kernel/walt-own,
# branch `own`; OPPO sched_assist on branch `oppo`, worktree walt-oppo), clang r547379, ThinLTO + CFI.
#   bash maintainer/kernel/build_walt.sh                  release config
#   DBG=1 bash ...                                        + pipa_bootdbg watchdog (test boots, logs via pstore)
#   TREE=... KCONFIG_EXTRA="-e PRINTK_TIME" bash ...      other tree / extra scripts/config args
#   CLEAN=0 bash ...                                      incremental
#   OUT=out-x KCONFIG_EXTRA="-d LOCKING_PROTECT" bash ... variant in its own output dir (feature bisects)
# Config = Lineage's fragment chain, as for its own sm8250 devices: vendor/kona-perf_defconfig + xiaomi/sm8250-common
# + xiaomi/pipa + our xiaomi/pipa-cos17 (+ xiaomi/pipa-oplus if the tree has it). arch/arm64/configs/pipa_defconfig is
# liyafe's old snapshot and is not used.
# Output: <tree>/out/arch/arm64/boot/Image. Pack with mkboot.sh (TRIM=1 for fastboot boot). Notes: kernel/KERNEL-RESEARCH.md
set -euo pipefail
K=${K:-$HOME/Documents/pipa/port-work/kernel}
TREE=${TREE:-$K/walt-own}
export PATH="$K/clang-r547379/bin:$PATH" KBUILD_BUILD_USER=stefan KBUILD_BUILD_HOST=pipa-cos17
OUT=${OUT:-out}
A=(ARCH=arm64 O="$OUT" CC=clang LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
   AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip)
cd "$TREE"
[ "${CLEAN:-1}" = 1 ] && rm -rf "$OUT"
mkdir -p "$OUT"
C=arch/arm64/configs/vendor
F=("$C/kona-perf_defconfig" "$C/xiaomi/sm8250-common.config" "$C/xiaomi/pipa.config" "$C/xiaomi/pipa-cos17.config")
[ -f "$C/xiaomi/pipa-oplus.config" ] && F+=("$C/xiaomi/pipa-oplus.config")
ARCH=arm64 LLVM=1 scripts/kconfig/merge_config.sh -O "$OUT" "${F[@]}" > "$OUT/merge_config.log" 2>&1 ||
	{ tail -20 "$OUT/merge_config.log"; exit 1; }
X=()
[ -d KernelSU ] && X+=(-e KSU -e KSU_SUSFS -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT
	-e KSU_SUSFS_SPOOF_UNAME -e KSU_SUSFS_ENABLE_LOG -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
	-e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -e KSU_SUSFS_OPEN_REDIRECT -e KSU_SUSFS_SUS_MAP)
# DBG: boot watchdog + lockup/hung-task detectors that panic, so an early hang warm-resets with its log in pstore
# (a 10 s power press is a hard reset: RAM and pstore are lost)
[ "${DBG:-0}" = 1 ] && X+=(-e PIPA_BOOTDBG -e SOFTLOCKUP_DETECTOR -e BOOTPARAM_SOFTLOCKUP_PANIC -e DETECT_HUNG_TASK
	-e BOOTPARAM_HUNG_TASK_PANIC --set-val DEFAULT_HUNG_TASK_TIMEOUT 60 -e PANIC_ON_OOPS)
[ ${#X[@]} -gt 0 ] || [ -n "${KCONFIG_EXTRA:-}" ] && scripts/config --file "$OUT/.config" "${X[@]}" ${KCONFIG_EXTRA:-}
make "${A[@]}" olddefconfig
make "${A[@]}" -j"$(nproc)"
ls -la "$OUT/arch/arm64/boot/Image"
