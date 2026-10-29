#!/bin/sh
# Build the frame capture test (BUGS-TODO 33). Output: out/framecap.dex.
set -eu
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/37.0.0
JAR=$SDK/platforms/android-37.0/android.jar
rm -rf out && mkdir -p out/classes
javac --release 17 -Xlint:-options -cp "$JAR" -d out/classes src/FrameTest.java
"$BT/d8" --release --min-api 35 --lib "$JAR" --output out out/classes/FrameTest.class
mv out/classes.dex out/framecap.dex
