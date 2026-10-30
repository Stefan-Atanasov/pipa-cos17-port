#!/bin/sh
# Build libpipa_facecrop.so (B7). Needs the NDK in ~/Android/Sdk/ndk (or NDK=, ANDROID_HOME=).
# Usage: build_facecrop.sh [outdir]   (default: the ROM copy, ../../port-rom/pipa_port/facehal/lib64)
set -eu
cd "$(dirname "$0")"
OUT=${1:-../../port-rom/pipa_port/facehal/lib64}
NDK=${NDK:-$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/ndk/* | sort -V | tail -1)}
CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang
"$CC" -shared -fPIC -O2 -Wall -Wextra -o "$OUT/libpipa_facecrop.so" facecrop.c -llog -ldl
"$NDK"/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip "$OUT/libpipa_facecrop.so"
md5sum "$OUT/libpipa_facecrop.so"
