#!/bin/sh
# Build the pipa AEC audio HAL wrapper (32-bit, like the vendor audio HAL). BUGS-TODO 27, step 5w.
# Headers: include/ = AOSP android-11.0.0_r48 (libhardware, system/media, system/core), Apache-2.0.
# Output: out/audio.primary.kona.so and a copy in port-rom/pipa_aec/ (the step 5w input).
set -eu
cd "$(dirname "$0")"
NDK=${NDK:-$HOME/Android/Sdk/ndk/30.0.16248370}
CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi30-clang
mkdir -p out ../../port-rom/pipa_aec
$CC -shared -fPIC -O2 -Wall -Wextra -Wno-unused-parameter -fvisibility=hidden \
    -Iinclude -o out/audio.primary.kona.so pipa_aec.c -llog -ldl -lm
cp out/audio.primary.kona.so ../../port-rom/pipa_aec/audio.primary.kona.so
md5sum out/audio.primary.kona.so
