#!/bin/sh
# Step 9l (BUGS-TODO 175, user 2026-11-26 "give BGMI the same as PUBG"): BGMI gets the PUBG MOBILE refresh rule.
# * system/my_product/etc/refresh_rate_config.xml (columns Auto-90-60-High120-FPSMax144, after 6r):
#   com.pubg.imobile (BGMI, OPPO CN donor entry, not tuned for this India-only game) "3-2-2-1-4", no flags
#   -> as com.tencent.ig: "3-1-2-1-4" disableViewOverride="true" adfr="true" (90 Hz setting: 90 instead of 60;
#   the game's own frame-rate request wins over view votes, as for PUBG MOBILE). Same engine and game.
set -eu
. "$PORT/lib.sh"
STEP=9l
echo "== 9l BGMI refresh rule = PUBG MOBILE"

X=$T/system/my_product/etc/refresh_rate_config.xml
[ -f "$X" ] || die "no $X"
need_grep '<item package="com.pubg.imobile" rateId="3-2-2-1-4" />' "$X"
need_grep '<item package="com.tencent.ig" rateId="3-1-2-1-4" disableViewOverride="true" adfr="true" />' "$X"
sed 's|<item package="com.pubg.imobile" rateId="3-2-2-1-4" />|<item package="com.pubg.imobile" rateId="3-1-2-1-4" disableViewOverride="true" adfr="true" />|' \
    "$X" > "$R/refresh.9l.xml"
need_grep '<item package="com.pubg.imobile" rateId="3-1-2-1-4" disableViewOverride="true" adfr="true" />' "$R/refresh.9l.xml"
python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$R/refresh.9l.xml" || die "XML broken"
cat "$R/refresh.9l.xml" > "$X"   # in place: owner, mode and SELinux label stay
rm -f "$R/refresh.9l.xml"
set_layer "$STEP"
