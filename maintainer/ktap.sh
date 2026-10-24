#!/system/bin/sh
# ktap.sh <x> <y>: tap at display (landscape, rotation 90) pixel x,y through the touchscreen's kernel input device,
# so in-kernel input handlers (uclamp_boost, devfreq_boost) see it like a finger. Used by maintainer/stress_switch.sh KTAP=1.
D=${KTAP_DEV:-/dev/input/event8}
# portrait panel 1800x2880 px, 10 units per px; ROTATION_90: panel_x = W - y, panel_y = x
px=$(( (1800 - $2) * 10 )); py=$(( $1 * 10 ))
[ -n "$KTAP_SWAP" ] && { px=$(( $2 * 10 )); py=$(( (2880 - $1) * 10 )); }
id=$(( $$ % 60000 + 1 ))
sendevent $D 3 47 0; sendevent $D 3 57 $id; sendevent $D 3 53 $px; sendevent $D 3 54 $py
sendevent $D 3 48 6; sendevent $D 3 58 60; sendevent $D 1 330 1; sendevent $D 0 0 0
sendevent $D 3 57 -1; sendevent $D 1 330 0; sendevent $D 0 0 0
