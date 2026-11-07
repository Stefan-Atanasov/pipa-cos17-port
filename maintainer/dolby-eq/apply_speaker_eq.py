#!/usr/bin/env python3
"""Apply the pipa (Xiaomi Pad 6) measured Dolby speaker EQ to a stock dax-default.xml.

    python3 apply_speaker_eq.py <stock dax-default.xml> <output xml> [--force]

The EQ (dB per band) is added to the audio optimizer (<band_optimizer>, 1/16 dB units, same 20 bands as the user
graphic EQ) of the 4 speaker tunings: speaker_landscape, speaker_portrait, speaker_volume_high, speaker_volume_low.
Headphone, Bluetooth and USB tunings are not changed; the user EQ in MiSound still works on top.
Install the result as /vendor/etc/dolby/dax-default.xml (same owner, mode and SELinux label as the original).
Dolby's DMS sees the new checksum and rebuilds /data/vendor/dolby/dax_sqlite3.db once (Dolby settings reset once).
Measured on pipa with stock HyperOS 2 libhwdap; for other devices the values do not apply.
"""
import hashlib, re, sys

STOCK_MD5 = "582003e70df30be8964df17610212ef3"   # pipa HyperOS 2 (OS2.0.13/OS2.0.16) dax-default.xml
BANDS_HZ = [47, 141, 234, 328, 469, 656, 844, 1031, 1313, 1688, 2250, 3000, 3750, 4688, 5813, 7125, 9000, 11250,
            13875, 19688]
EQ_DB = [4.62, 10.62, 3.62, 1.62, 1.62, -1.38, -3.88, -4.88, -3.17, -0.07, 0.62, 0.12, -0.88, -2.88, -2.38, -3.38,
         -1.88, 1.62, 1.62, -1.38]
TUNINGS = ("speaker_landscape", "speaker_portrait", "speaker_volume_high", "speaker_volume_low")

def main():
    args = [a for a in sys.argv[1:] if a != "--force"]
    if len(args) != 2:
        sys.exit(__doc__)
    data = open(args[0], "rb").read()
    md5 = hashlib.md5(data).hexdigest()
    if md5 != STOCK_MD5 and "--force" not in sys.argv:
        sys.exit("not the stock pipa HyperOS 2 file (md5 %s); use --force to apply anyway" % md5)
    s = data.decode()
    add = [round(v * 16) for v in EQ_DB]
    for t in TUNINGS:
        a = s.index('<tuning name="%s"' % t)
        b = s.index('</tuning>', a)
        blk, n = s[a:b], [0]
        def f(m):
            k = n[0]; n[0] += 1
            if int(m.group(1)) != BANDS_HZ[k]:
                sys.exit("%s: band %d is %s Hz, expected %d" % (t, k, m.group(1), BANDS_HZ[k]))
            return '<band_optimizer frequency="%s" gain_left="%d" gain_right="%d"/>' % (
                m.group(1), int(m.group(2)) + add[k], int(m.group(3)) + add[k])
        nb = re.sub(r'<band_optimizer frequency="(\d+)" gain_left="(-?\d+)" gain_right="(-?\d+)"/>', f, blk)
        if n[0] != 20:
            sys.exit("%s: %d optimizer bands, expected 20" % (t, n[0]))
        s = s[:a] + nb + s[b:]
    open(args[1], "w").write(s)
    print("written %s (md5 %s)" % (args[1], hashlib.md5(s.encode()).hexdigest()))

if __name__ == "__main__":
    main()
