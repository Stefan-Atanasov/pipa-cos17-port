#!/bin/bash
# BUGS-TODO 66: PC Screen Extend / PC Screen Mirror (OPPO PC Connect) give a black tablet screen.
# com.oplus.ortc.AndroidVideoDecoder.initDecodeInternal() (system_ext/framework/oplusex/com.oplus.odmf/odmf.jar) sets
# MediaFormat "color-format" = 19 (YUV420Planar, a byte-buffer format) also when it decodes straight to a Surface
# (sharedContext == null). pipa's HIDL c2@1.0 decoder then allocates linear CPU-read buffers (usage 0x10003) and refuses
# the consumer usage (BAD_INDEX), so the buffers have no HW_COMPOSER/HW_TEXTURE usage: the composer sends the layer to
# the GPU, and SurfaceFlinger cannot sample it ("blacked out as buffer is not gpu readable"). The patch skips the
# color-format key (if-nez -> goto): the decoder picks its own surface format. Tested live 2026-11-04 (both modes work).
#   patch_odmf_pcextend.sh <odmf.jar in> <odmf.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS='com/oplus/ortc/AndroidVideoDecoder.smali'

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$(basename "$d" .dex)"
    [ -f "$W/sm_$(basename "$d" .dex)/$CLS" ] && DEX=$(basename "$d")
done
[ -n "$DEX" ] || { echo "no AndroidVideoDecoder in odmf.jar"; exit 1; }
SM=$W/sm_${DEX%.dex}
python3 - "$SM/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method private initDecodeInternal(II)Lcom/oplus/ortc/VideoCodecStatus;\n'
assert s.count(head) == 1, "initDecodeInternal not found once"
a = s.index(head); b = s.index('.end method', a); body = s[a:b]
pat = re.compile(r'(iget-object (p\d+|v\d+), p0, Lcom/oplus/ortc/AndroidVideoDecoder;->sharedContext:Lcom/oplus/ortc/EglBase\$Context;\n'
                 r'(?:\s*\.line \d+\n|\s*\n)*\s*)if-nez \2, (:cond_\w+)(\n(?:\s*\.line \d+\n|\s*\n)*\s*const-string \w+, "color-format"\n)')
m = list(pat.finditer(body))
assert len(m) == 1, "color-format block not as expected (%d matches)" % len(m)
body = body[:m[0].start()] + m[0].group(1) + 'goto/16 ' + m[0].group(3) + m[0].group(4) + body[m[0].end():]
open(p, 'w').write(s[:a] + body + s[b:])
print("patched: no color-format in surface mode")
PY
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$SM" -o "$W/$DEX.new"

python3 - "$IN" "$OUT" "$W/$DEX.new" "$DEX" <<'PY'
import sys, zipfile
src, dst, dex, name = sys.argv[1:]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst + ".tmp", "w") as zo:
    for e in zi.infolist():
        data = open(dex, "rb").read() if e.filename == name else zi.read(e)
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
PY
"$BT/zipalign" -f -p 4 "$OUT.tmp" "$OUT"; rm -f "$OUT.tmp"
"$BT/zipalign" -c -p 4 "$OUT" >/dev/null && echo "ok: $OUT $(md5sum < "$OUT" | cut -c1-32)"
