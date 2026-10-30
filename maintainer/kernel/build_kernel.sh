#!/bin/bash
# Build the pipa COS17 kernel: E404R staging-bpf + SukiSU builtin (uapi 6) + susfs 2.3.0 + audit.
#   bash maintainer/kernel/build_kernel.sh            (tree: port-work/kernel/e404-own, toolchain: clang r547379)
#   TREE=... KCONFIG_EXTRA="-e PRINTK_TIME" bash ...   (other tree / extra scripts/config args)
# Output: <tree>/out/arch/arm64/boot/{Image,dtb,dtbo.img}. Notes: kernel/KERNEL-RESEARCH.md
set -euo pipefail
K=${K:-${PIPA_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/port-work/kernel}
TREE=${TREE:-$K/e404-own}
export PATH="$K/clang-r547379/bin:$PATH" KBUILD_BUILD_USER=stefan KBUILD_BUILD_HOST=pipa-cos17
A=(ARCH=arm64 O=out CC=clang LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
   AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip)
cd "$TREE"
[ "${CLEAN:-1}" = 1 ] && rm -rf out
make "${A[@]}" vendor/pipa_defconfig
scripts/config --file out/.config -e KSU -e KSU_SUSFS -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT \
  -e KSU_SUSFS_SPOOF_UNAME -e KSU_SUSFS_ENABLE_LOG -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
  -e KSU_SUSFS_OPEN_REDIRECT -e KSU_SUSFS_SUS_MAP -e AUDIT -e AUDITSYSCALL -e KALLSYMS -e KALLSYMS_ALL ${KCONFIG_EXTRA:-}
make "${A[@]}" olddefconfig
make "${A[@]}" -j"$(nproc)"
ls -la out/arch/arm64/boot/{Image,dtb,dtbo.img}
