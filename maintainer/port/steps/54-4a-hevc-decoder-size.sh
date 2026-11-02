#!/bin/sh
# Phase 4a: live wallpapers ("Ivy" and other O-Live video wallpapers) are not black (BUGS-TODO 56, public bug doc
# 2026-11-02; vendor only).
#
# The wallpapers are 2500x2500 HEVC Main10 videos. vendor/etc/media_codecs_c2.xml (beta4 = HyperOS) caps
# c2.qti.hevc.decoder at 4096x2304, so MediaPlayer took the software decoder c2.android.hevc.decoder, which fails
# ("work failed to complete: 14") and the wallpaper stayed black. The Venus decoder plays it (the wallpaper app's
# ExoPlayer preview used it). New limit: 4096x4096 with a block-count cap equal to the old area (4096x2304 / 16x16 =
# 36864 blocks): no larger frame than before, only square and portrait shapes now fit. Live test 2026-11-02 (bind mount +
# ctl.restart media): wallpaper plays on c2.qti.hevc.decoder.
#NEEDS: "$PORT/lib.sh"
set -eu
. "$PORT/lib.sh"

F=$T/vendor/etc/media_codecs_c2.xml
replace_once "$F" \
'        <MediaCodec name="c2.qti.hevc.decoder" type="video/hevc" >\n            <Limit name="size" min="128x128" max="4096x2304" />\n' \
'        <MediaCodec name="c2.qti.hevc.decoder" type="video/hevc" >\n            <Limit name="size" min="128x128" max="4096x4096" />\n            <Limit name="block-count" range="1-36864" />\n'
need_grep 'range="1-36864"' "$F"
