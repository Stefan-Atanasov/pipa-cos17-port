#!/usr/bin/env python3
"""Give the VoIP capture front end (MultiMedia10) an echo reference also outside MODE_IN_COMMUNICATION.

Why: call sharing (com.oplus.vdc) plays the far end with usage VOICE_COMMUNICATION and records the mic
with source VOICE_COMMUNICATION. The HAL records on `audio-record-voip` = MultiMedia10, so the DSP echo
canceller reads its reference from `AUDIO_REF_EC_UL10 MUX`. But the call is a telephony call, so the
mode is MODE_IN_CALL, and the CAF HAL (platform_set_echo_reference) appends "-voip" to the path name only
in MODE_IN_COMMUNICATION. It applies `echo-reference <device>`, which sets only `AUDIO_REF_EC_UL1 MUX`
(MultiMedia1). UL10 stays None: no reference, and the far end hears its own voice (BUGS-TODO 27).

Each non-voip `echo-reference*` path that sets `AUDIO_REF_EC_UL1 MUX` gets the same value also for
`AUDIO_REF_EC_UL10 MUX`, in the base file and in Xiaomi's static overlay (the overlay cannot add paths, so
both files get the line). A UL10 reference with no MultiMedia10 stream does nothing. The base file also
gets `echo-reference handset` (the overlay has `-voip handset`, but no plain one).

usage: patch_ec_ref.py base|overlay <in.xml> <out.xml>
"""
import re
import sys

UL1 = "AUDIO_REF_EC_UL1 MUX"
UL10 = "AUDIO_REF_EC_UL10 MUX"
# a non-voip echo-reference path element
PATH_RE = re.compile(r'<path name="echo-reference(?: [^"]*)?">.*?</path>', re.S)
CTL_RE = re.compile(r'([ \t]*)<ctl name="' + re.escape(UL1) + r'" value="([^"]+)"\s*/>\n')

HANDSET = '''    <path name="echo-reference handset">
        <ctl name="EC Reference Channels" value="One"/>
        <ctl name="AUDIO_REF_EC_UL1 MUX" value="TERT_TDM_RX_0" />
        <ctl name="AUDIO_REF_EC_UL10 MUX" value="TERT_TDM_RX_0" />
    </path>

'''


def patch(kind, text):
    if UL10 in "".join(m.group(0) for m in PATH_RE.finditer(text)):
        raise SystemExit("already patched")
    added = 0

    def mirror(m):
        nonlocal added
        path = m.group(0)
        c = CTL_RE.search(path)
        if not c:
            return path
        added += 1
        line = f'{c.group(1)}<ctl name="{UL10}" value="{c.group(2)}" />\n'
        return path[:c.end()] + line + path[c.end():]

    text = PATH_RE.sub(mirror, text)
    if kind == "base":
        anchor = '    <path name="echo-reference-voip">'
        if '"echo-reference handset"' in text or text.count(anchor) != 1:
            raise SystemExit("base anchor not found")
        text = text.replace(anchor, HANDSET + anchor)
    if added == 0:
        raise SystemExit("no echo-reference path with " + UL1)
    print(f"{kind}: {added} paths mirrored to UL10", file=sys.stderr)
    return text


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("base", "overlay"):
        raise SystemExit(__doc__)
    with open(sys.argv[2]) as f:
        text = f.read()
    with open(sys.argv[3], "w") as f:
        f.write(patch(sys.argv[1], text))


if __name__ == "__main__":
    main()
