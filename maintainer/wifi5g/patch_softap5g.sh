#!/bin/bash
# Hotspot 5 GHz band (BUGS 171, 2026-11-25): pipa's vendor Wi-Fi HAL does not support getUsableChannels (NOT_SUPPORTED,
# code 4), so OplusSoftapP2pBandControl.getFreqListForBand gets empty channel lists and canUseSoftap5GBand() returns
# false: Settings > Personal hotspot offers 2.4 GHz only. OPPO's own fallback ("cannot get channel list from driver")
# returns true only for countries in a RUS list (CN, IN, US), and the country reads as null here. The patch drops the
# country condition of that fallback only: 5 GHz when WifiManager.is5GHzBandSupported() and the driver gives no
# list. OPPO's 2.4 GHz-only region check (isSoftapInOnly2GRegion: JP, MA, EG, ...) runs before it and stays.
#   patch_softap5g.sh <oplus-wifi-service.jar in> <oplus-wifi-service.jar out>
# Needs JDK 21, ~/Android/Sdk build-tools 37, tools/smali (2.5.2). Stops on any surprise. smali/baksmali with -j 1.
set -euo pipefail
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
SMALI=$HERE/../../../tools/smali
SDK=${ANDROID_HOME:-$HOME/Android/Sdk}; BT=$SDK/build-tools/37.0.0
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CLS=com/oplus/server/wifi/hotspot/OplusSoftapP2pBandControl.smali

unzip -q "$IN" 'classes*.dex' -d "$W"
DEX=
for d in "$W"/classes*.dex; do
    n=$(basename "$d" .dex)
    java -jar "$SMALI/baksmali-2.5.2.jar" d -j 1 -a 36 "$d" -o "$W/sm_$n"
    [ -f "$W/sm_$n/$CLS" ] && DEX=$n.dex
done
[ -n "$DEX" ] || { echo "no OplusSoftapP2pBandControl in the jar"; exit 1; }
SM=$W/sm_${DEX%.dex}
python3 -I - "$SM/$CLS" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
head = '.method public final canUseSoftap5GBand()Z\n'
assert s.count(head) == 1, "canUseSoftap5GBand()Z not found once"
a = s.index(head); b = s.index('.end method', a); body = s[a:b]
assert body.count('"isSoftApDefault5GBandSupportedRegion country = null"') == 1, "fallback country check not found once"
pat = re.compile(r'(    invoke-virtual \{p0, v\d+, v\d+, v\d+\}, Lcom/oplus/server/wifi/hotspot/OplusSoftapP2pBandControl;'
                 r'->isCountryInList\(Ljava/lang/String;Ljava/util/List;Ljava/lang/String;\)Z\n\s*\n?    move-result (p0|v\d+)\n)')
m = [x for x in pat.finditer(body) if 'isSoftApDefault5GBandSupportedRegion' in body[max(0, x.start() - 300):x.start()]]
assert len(m) == 1, "isCountryInList of the fallback not found once (%d)" % len(m)
body = body[:m[0].start()] + '    const/4 %s, 0x1\n' % m[0].group(2) + body[m[0].end():]
open(p, 'w').write(s[:a] + body + s[b:])
print("patched: canUseSoftap5GBand fallback without the country list (" + m[0].group(2) + ")")
PY
java -jar "$SMALI/smali-2.5.2.jar" a -j 1 -a 36 "$SM" -o "$W/$DEX.new"
python3 -I - "$IN" "$OUT" "$W/$DEX.new" "$DEX" <<'PY'
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
