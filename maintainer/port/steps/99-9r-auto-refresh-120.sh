#!/bin/sh
# Step 9r (BUGS 210, user 2026-11-27 "launcher runs at 120 in Auto, why lock screen 144"): Auto refresh like the donor
# (OPPO Pad Mini, 120 Hz panel). The beta4 porter's refresh_rate_config.xml has defaultRateId 0-0-0-0-4: in Auto (secure
# oplus_customize_screen_refresh_rate 0) windows without a rule got the panel maximum (144).
# * my_product refresh_rate_config.xml: defaultRateId Auto column 0 -> 3 (120). defaultMaxRate stays 144: it caps
#   app-requested rates, zoom windows and the app-switch boost (adjustRefreshForDefaultMax), so 120 there broke
#   "FPS Max 144 Hz" for games (pt175-pt176).
# * The 144 Hz lock screen in each mode: step 9s. The pt175-pt176 service peak_check is removed (9s).
set -eu
. "$PORT/lib.sh"
STEP=9r
echo "== 9r Auto refresh: 120 default like the Pad Mini"

X=$T/system/my_product/etc/refresh_rate_config.xml
[ -f "$X" ] || die "no $X"
need_grep 'defaultMaxRate="144" defaultRateId="0-0-0-0-4"' "$X"
sed 's|defaultMaxRate="144" defaultRateId="0-0-0-0-4"|defaultMaxRate="144" defaultRateId="3-0-0-0-4"|' "$X" > "$R/refresh.9r.xml"
need_grep 'defaultMaxRate="144" defaultRateId="3-0-0-0-4"' "$R/refresh.9r.xml"
python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$R/refresh.9r.xml" || die "XML broken"
cat "$R/refresh.9r.xml" > "$X"   # in place: owner, mode and SELinux label stay
rm -f "$R/refresh.9r.xml"
