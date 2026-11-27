#!/bin/sh
# Builds fbgctl (static arm64) with the NDK into port-rom/pipa_port/fbgctl (BUGS 175, gameopt shim prime-core bind).
set -eu
cd "$(dirname "$0")"
NDK=$(ls -d ~/Android/Sdk/ndk/* | tail -1)
"$NDK"/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang -O2 -Wall -Wextra -Werror -static -s \
    -o ../../port-rom/pipa_port/fbgctl fbgctl.c
file ../../port-rom/pipa_port/fbgctl
