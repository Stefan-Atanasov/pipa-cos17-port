#!/usr/bin/env python3
"""Let the PixelOS composer skip SET_LAYER_GENERIC_METADATA instead of dropping the frame (BUGS-TODO 29).

The port's vendor display stack is PixelOS's (vendor.qti.hardware.display.composer-service, md5 d527dacc...). During
HDR video the ColorOS SurfaceFlinger sends IComposerClient command 0x040e0000 (SET_LAYER_GENERIC_METADATA, composer
2.4) every frame. The composer has no handler: QtiComposerClient::CommandReader::parseCommonCmd() (0x25860) returns
parsed=false, parse() (0x23290) logs "failed to parse command 0x40e0000, length 19" and stops reading the command
buffer, so the rest of that frame's commands are lost: the screen glitches and does not respond while HDR plays
(seen on the 3i test layer, 2026-10-28). Analysis: port-work/codex/composer-hdr10plus-answer.md.

Patch (1 instruction): the last compare of the dispatch chain, at 0x25fa4
    b.ne 0x26620        ; no match -> return parsed=false
becomes
    b.ne 0x26608        ; no match -> mov w21, #1 -> return parsed=true
parse() then moves the cursor to the end of the command (the length from the command header, 0x233d0-0x233ec), so the
unknown command is skipped and the frame goes on. The QTI vendor commands (0x08000000, 0x08010000) are handled in
parse() before parseCommonCmd and do not reach this point. Known commands keep their handlers.

usage: patch_composer_genmeta.py <composer-service in> <composer-service out>
md5-gated: stops on any other composer build.
"""
import hashlib
import sys

MD5_IN = "d527dacc2348c7efae42154ddd0e37d7"
OFF = 0x25FA4                       # VA = file offset (executable LOAD segment starts at offset = VA 0x1e000)
OLD = bytes.fromhex("e1330054")     # b.ne 0x26620
NEW = bytes.fromhex("21330054")     # b.ne 0x26608
CHECK = (0x26608, bytes.fromhex("3500805205000014"))   # mov w21, #1 ; b 0x26620


def main():
    src, dst = sys.argv[1:3]
    d = bytearray(open(src, "rb").read())
    md5 = hashlib.md5(d).hexdigest()
    if md5 != MD5_IN:
        sys.exit(f"{src}: md5 {md5}, expected {MD5_IN} (other composer build: find the site again)")
    if d[OFF:OFF + 4] != OLD or d[CHECK[0]:CHECK[0] + len(CHECK[1])] != CHECK[1]:
        sys.exit("unexpected bytes at the patch site")
    d[OFF:OFF + 4] = NEW
    open(dst, "wb").write(d)
    print(f"{dst}: 0x{OFF:x} b.ne 0x26620 -> b.ne 0x26608, md5 {hashlib.md5(d).hexdigest()}")


if __name__ == "__main__":
    main()
