#!/bin/bash
# Step 3o: per-app device identity (src/com/android/internal/util/pipa/PipaAppIdentity.java).
# Adds PipaAppIdentity to classes6.dex of framework.jar and calls PipaAppIdentity.set(context) at the start of both
# Instrumentation.newApplication methods (classes.dex). Netflix sees a Pixel 6, Google Photos a Pixel XL.
#   patch_propspoof.sh <framework.jar in> <framework.jar out>
# Needs JDK 21, ~/Android/Sdk (build-tools 37, platform 37.0), tools/apktool/apktool.jar 2.12.1 (its smali 3.x keeps
# the hidden-API flags; smali 2.5.2 cannot read them in the C.06 framework dex). Only the smali part of apktool is
# used (jar without resources). The user allowed apktool for this on 2026-10-29. Stops on any surprise.
# Round trip of the unchanged C.06 dex files: same smali, except Activity.setDisablePreviewScreenshots (public SDK
# API): its hidden-API flag has no smali name and becomes "whitelist".
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
APKTOOL=$HERE/../../../tools/apktool/apktool.jar
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0; JAR=$SDK/platforms/android-37.0/android.jar
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
INS=android/app/Instrumentation.smali
NEW=com/android/internal/util/pipa/PipaAppIdentity.smali
[ "$(sha256sum < "$APKTOOL" | cut -c1-64)" = 66cf4524a4a45a7f56567d08b2c9b6ec237bcdd78cee69fd4a59c8a0243aeafa ] || { echo "apktool.jar is not 2.12.1"; exit 1; }
apktool() { java -jar "$APKTOOL" "$@"; }
# a jar with only the given dex files (apktool names the smali folders after them)
mkjar() { python3 -I - "$@" <<'PY'
import sys, zipfile, os
out, *dex = sys.argv[1:]
with zipfile.ZipFile(out, "w") as z:
    for d in dex: z.write(d, os.path.basename(d))
PY
}

mkdir -p "$W/cls" "$W/dex" "$W/x"
javac --release 17 -nowarn -cp "$JAR" -d "$W/cls" "$HERE/src/com/android/internal/util/pipa/PipaAppIdentity.java"
"$BT/d8" --release --min-api 35 --lib "$JAR" --output "$W/dex" "$W"/cls/com/android/internal/util/pipa/*.class
mkjar "$W/new.jar" "$W/dex/classes.dex"
apktool d -q -r -f -j 1 -api 36 "$W/new.jar" -o "$W/new"

unzip -q "$IN" classes.dex classes6.dex -d "$W/x"
mkjar "$W/two.jar" "$W/x/classes.dex" "$W/x/classes6.dex"
apktool d -q -r -f -j 1 -api 36 "$W/two.jar" -o "$W/sm"
[ -f "$W/sm/smali/$INS" ] || { echo "no $INS in classes.dex"; exit 1; }
[ ! -e "$W/sm/smali/$NEW" ] && [ ! -e "$W/sm/smali_classes6/$NEW" ] || { echo "already patched"; exit 1; }
mkdir -p "$W/sm/smali_classes6/$(dirname "$NEW")"
cp "$W/new/smali/$NEW" "$W/sm/smali_classes6/$NEW"
python3 -I - "$W/sm/smali/$INS" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
# (method head, register that holds the Context)
sites = [(".method public static whitelist newApplication(Ljava/lang/Class;Landroid/content/Context;)Landroid/app/Application;", "p1"),
         (".method public whitelist newApplication(Ljava/lang/ClassLoader;Ljava/lang/String;Landroid/content/Context;)Landroid/app/Application;", "p3")]
for head, reg in sites:
    assert s.count(head + "\n") == 1, "not found once: " + head
    a = s.index(head + "\n"); b = s.index("\n.end method", a)
    body = s[a:b]
    assert "PipaAppIdentity" not in body
    i = body.index("\n    .line ")   # first code line: after .locals, .param and the annotations
    call = "\n    invoke-static {%s}, Lcom/android/internal/util/pipa/PipaAppIdentity;->set(Landroid/content/Context;)V\n" % reg
    s = s[:a] + body[:i] + call + body[i:] + s[b:]
assert s.count("PipaAppIdentity;->set(") == 2
open(p, "w").write(s)
PY
apktool b -q -j 1 -api 36 "$W/sm" -o "$W/built.jar"
mkdir -p "$W/b"; unzip -q "$W/built.jar" classes.dex classes6.dex -d "$W/b"
python3 -I - "$W/b/classes.dex" "$W/b/classes6.dex" <<'PY'
import sys, struct
for p in sys.argv[1:]:
    h = open(p, "rb").read(0x70)
    assert h[:8] == b"dex\n039\0", p + ": not dex 039"
    m, f = struct.unpack_from("<I", h, 0x58)[0], struct.unpack_from("<I", h, 0x50)[0]
    assert m <= 65536 and f <= 65536, p + ": too many ids"
    print("%s: %d methods, %d fields" % (p.rsplit("/", 1)[1], m, f))
PY

# new jar: same entries in the same order, classes.dex and classes6.dex replaced, same compression per entry
python3 -I - "$IN" "$OUT" "$W/b" <<'PY'
import sys, zipfile, os
src, dst, b = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w") as zo:
    for e in zi.infolist():
        if e.filename in ("classes.dex", "classes6.dex"):
            data = open(os.path.join(b, e.filename), "rb").read()
        else:
            data = zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
