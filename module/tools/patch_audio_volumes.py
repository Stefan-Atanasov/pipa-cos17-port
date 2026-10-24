#!/usr/bin/env python3
"""Add DEVICE_CATEGORY_USB_HEADSET and DEVICE_CATEGORY_A2DP volume curves to pipa's audio_policy_volumes.xml.

Why: the ColorOS audio policy (libaudiopolicycomponents / libaudiopolicyextimpl) adds two
device categories of its own, DEVICE_CATEGORY_A2DP (5) and DEVICE_CATEGORY_USB_HEADSET (6), and
files USB headsets/DACs under category 6. The port's vendor volume table comes from Xiaomi and
only defines the five AOSP categories. With no curve for category 6,
VolumeCurves::volIndexToDb() logs "Invalid device category 6 for Volume Curve" and returns
0 dB, so a USB DAC always plays at full scale whatever the volume slider says. Bluetooth (category
5) has the same gap; it only shows on headsets without absolute volume, where the stream index is
applied in software.

The engine imports TypeConverter<device_category>::mTable from libaudiopolicycomponents, whose
table knows both OPLUS names, so the legacy volume parser accepts the new entries.

Every DEVICE_CATEGORY_HEADSET <volume> element (inline points or ref=) is duplicated right after
itself with the category renamed, so USB and Bluetooth headsets get exactly the wired-headset
curves (AOSP files A2DP under DEVICE_CATEGORY_HEADSET too).

usage: patch_audio_volumes.py <in.xml> <out.xml>
"""
import re
import sys

SRC_CAT = "DEVICE_CATEGORY_HEADSET"
NEW_CATS = ["DEVICE_CATEGORY_USB_HEADSET", "DEVICE_CATEGORY_A2DP"]

# one <volume .../> or <volume ...>...</volume> element, with its leading indentation
VOLUME_RE = re.compile(r'([ \t]*)<volume\b[^>]*?(?:/>|>.*?</volume>)', re.S)


def patch(text):
    if any(f'deviceCategory="{c}"' in text for c in NEW_CATS):
        raise SystemExit("already patched")
    added = 0

    def dup(m):
        nonlocal added
        elem = m.group(0)
        if f'deviceCategory="{SRC_CAT}"' not in elem:
            return elem
        copies = [elem.replace(f'deviceCategory="{SRC_CAT}"', f'deviceCategory="{c}"')
                  for c in NEW_CATS]
        added += len(copies)
        return "\n".join([elem] + copies)

    out = VOLUME_RE.sub(dup, text)
    if not added:
        raise SystemExit(f"no {SRC_CAT} volume entries found")
    return out, added


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        text = f.read()
    out, added = patch(text)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(out)
    print(f"added {added} volume curves")


if __name__ == "__main__":
    main()
