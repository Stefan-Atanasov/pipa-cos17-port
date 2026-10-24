#!/bin/sh
# Builds kgest (static arm64) with the NDK.
cd "$(dirname "$0")"
NDK=$(ls -d ~/Android/Sdk/ndk/* | tail -1)
"$NDK"/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang -O2 -static -o kgest kgest.c
