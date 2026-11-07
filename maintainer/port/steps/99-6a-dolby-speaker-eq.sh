#!/bin/sh
# Phase 6a (beta8): measured speaker EQ in the Dolby speaker tunings + stock Dolby tuning-control props.
#
# 1. Speaker EQ (user decision 2026-11-06: ROM default, user EQ stays free on top). Measured on pipa (port pt72,
#    profile 0 Dynamic, landscape, Fifine A6NEO at ~35 cm, pink noise, notes/DOLBY-SPEAKER-TUNING-20261106.md):
#    stock Dolby is close to stock HyperOS (Notebookcheck pink noise) above 300 Hz; target "neutral but slightly fun"
#    (Harman/JBL-like): deeper bass (+10 dB at 127-160 Hz, 200-250 Hz kept below), mids flat (+-2.5 dB 320 Hz - 8 kHz),
#    3 kHz notch softened, a little air. 2026-11-07: -1 dB more at 7.1 / 9 kHz (listening A/B, user choice "B1"). Added to the audio optimizer (Dolby's per-tuning speaker correction, same 20
#    bands and 1/16 dB units as the user graphic EQ) of the 4 speaker tunings, so MiSound's EQ still works on top and
#    headphone / Bluetooth / USB are unchanged. Dolby's regulator (unchanged) caps the bass at high volume.
#    DMS sees the new file checksum and rebuilds /data/vendor/dolby/dax_sqlite3.db once (Dolby settings reset once).
# 2. vendor.audio.dolby.control.support / .tunning.by.volume.support=true are in the vendor build.prop (stock lines,
#    vendor_audio_prop). PipaHelper 1.3 (DolbyKeeper, priv_app) reads them for the stock tuning selection, as
#    system_server's DolbyEffectController does on HyperOS: rules_6a_system_ext.cil lets priv_app read the type
#    (secilc exit 0, neverallow 76 = without the rule).
#NEEDS: "$HERE/sepolicy/rules_6a_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=6a

X=$T/vendor/etc/dolby/dax-default.xml
[ "$(md5sum < "$X" | cut -d' ' -f1)" = 582003e70df30be8964df17610212ef3 ] || die "dax-default.xml is not the stock HyperOS 2 file"
python3 - "$X" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
# dB per band (47 Hz ... 19688 Hz), 1/16 dB in the file
eq = [4.62, 10.62, 3.62, 1.62, 1.62, -1.38, -3.88, -4.88, -3.17, -0.07, 0.62, 0.12, -0.88, -2.88, -2.38, -4.38,
      -2.88, 1.62, 1.62, -1.38]
add = [round(v * 16) for v in eq]
for t in ("speaker_landscape", "speaker_portrait", "speaker_volume_high", "speaker_volume_low"):
    a = s.index('<tuning name="%s"' % t); b = s.index('</tuning>', a)
    blk = s[a:b]; i = [0]
    def f(m):
        k = i[0]; i[0] += 1
        return '<band_optimizer frequency="%s" gain_left="%d" gain_right="%d"/>' % (
            m.group(1), int(m.group(2)) + add[k], int(m.group(3)) + add[k])
    nb = re.sub(r'<band_optimizer frequency="(\d+)" gain_left="(-?\d+)" gain_right="(-?\d+)"/>', f, blk)
    if i[0] != 20: sys.exit("%s: %d optimizer bands" % (t, i[0]))
    s = s[:a] + nb + s[b:]
open(p, 'w').write(s)   # same inode (open for write), owner, mode and label
EOF
echo "edited  vendor/etc/dolby/dax-default.xml (speaker audio optimizer)"
need_grep '^vendor.audio.dolby.control.support=true' "$T/vendor/build.prop"
need_grep '^vendor.audio.dolby.control.tunning.by.volume.support=true' "$T/vendor/build.prop"
SE=$T/system_ext/etc/selinux
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/$f" ] || continue
    forbid_grep "pipa port 6a" "$SE/$f"
    { cat "$SE/$f"; cat "$HERE/sepolicy/rules_6a_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 6a" "$SE/$f"
    echo "edited  system_ext/etc/selinux/$f"
done
md5sum "$X"
set_layer "$STEP"
