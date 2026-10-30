#!/bin/sh
# Build libpipa_eyeguard.so (item 8). Needs the NDK in ~/Android/Sdk/ndk.
# Usage: build_eyeguard.sh [outdir]   (default: the ROM copy, ../../port-rom/pipa_port/facehal/lib64)
set -eu
cd "$(dirname "$0")"
OUT=${1:-../../port-rom/pipa_port/facehal/lib64}
NDK=${NDK:-$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/ndk/* | sort -V | tail -1)}
BIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
"$BIN"/aarch64-linux-android35-clang -shared -fPIC -O2 -Wall -Wextra -o "$OUT/libpipa_eyeguard.so" eyeguard.c -llog -ldl
"$BIN"/llvm-strip "$OUT/libpipa_eyeguard.so"
md5sum "$OUT/libpipa_eyeguard.so"
