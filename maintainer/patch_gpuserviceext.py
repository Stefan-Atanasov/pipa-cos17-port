#!/usr/bin/env python3
"""Null-guard OPPO's gpuservice extension (system_ext/lib64/libgpuserviceextimpl.so).

GpuServiceExtImpl::onTransact forwards six binder codes (0xbb9 load, 0xbba getAppInfo, 0xbbb writeAllRePathInfos,
0xbc5 queryWarmupGate, 0xbc6 notifyWarmupDone, 0xbc7 handleRuntimeConfig) to the PreCacheService at this+0x68
without a null check. That pointer is set only after GpuMem::initialize(), which waits 30 s when the kernel has no
gpu_mem tracepoint (our E404 kernel), so every app starting EGL in that window crashes gpuservice.
Patch: each forwarding site returns 0 when the pointer is null. Sites 0xbba..0xbc7 drop a redundant
`ldp x20, x19` (x19/x20 are untouched on those paths) to make room for a cbz; the 0xbb9 site jumps to a 16-byte
stub placed right after .plt, and the R+X segment grows by that much.

  python3 maintainer/patch_gpuserviceext.py <in.so> <out.so>
Only the build with md5 f58c0678f969b718a91398495a5358c9 (C.06 / beta5) is accepted.
"""
import hashlib
import struct
import sys

SRC_MD5 = 'f58c0678f969b718a91398495a5358c9'
RET0 = 0x221f8          # mov w0, wzr; epilogue; ret
LOAD_PLT = 0x23088      # PreCacheService::load@plt
CAVE = 0x246e0          # after .plt (ends 0x246d8), same page, zero padding in the file
LDP_X20_X19 = bytes.fromhex('f44f43a9')   # ldp x20, x19, [sp, #0x30]
LDR_X0_68 = bytes.fromhex('003440f9')     # ldr x0, [x0, #0x68]


def cbz_x0(pc, target):
    return struct.pack('<I', 0xB4000000 | ((((target - pc) >> 2) & 0x7FFFF) << 5))


def branch(pc, target, link=False):
    return struct.pack('<I', (0x94000000 if link else 0x14000000) | (((target - pc) >> 2) & 0x3FFFFFF))


def main(src, dst):
    d = bytearray(open(src, 'rb').read())
    if hashlib.md5(d).hexdigest() != SRC_MD5:
        sys.exit('unexpected input md5 (not the C.06/beta5 build); re-check the offsets before patching')

    # ldr x0,[x0,#0x68]; <movs>; ldp x20,x19 -> ldr; cbz x0,RET0; <movs>
    for site, nmov in ((0x22198, 2), (0x221c8, 2), (0x22210, 2), (0x2224c, 2), (0x22230, 1)):
        assert d[site:site + 4] == LDR_X0_68, hex(site)
        ldp = site + 4 + 4 * nmov
        assert d[ldp:ldp + 4] == LDP_X20_X19, hex(site)
        movs = bytes(d[site + 4:ldp])
        d[site + 4:ldp + 4] = cbz_x0(site + 4, RET0) + movs

    # 0xbb9: ldr x0,[x0,#0x68]; bl load -> b CAVE; CAVE: ldr; cbz x0,RET0; bl load; b RET0
    assert d[0x221f0:0x221f4] == LDR_X0_68 and d[0x221f4:0x221f8] == branch(0x221f4, LOAD_PLT, True)
    assert d[CAVE:CAVE + 16] == bytes(16)
    d[0x221f0:0x221f4] = branch(0x221f0, CAVE)
    d[CAVE:CAVE + 16] = (LDR_X0_68 + cbz_x0(CAVE + 4, RET0) + branch(CAVE + 8, LOAD_PLT, True)
                         + branch(CAVE + 12, RET0))

    # grow the R+X LOAD (offset 0xf000) to cover the stub
    phoff, = struct.unpack_from('<Q', d, 0x20)
    phentsize, phnum = struct.unpack_from('<HH', d, 0x36)
    for i in range(phnum):
        ph = phoff + i * phentsize
        p_type, p_flags, p_offset = struct.unpack_from('<IIQ', d, ph)
        if p_type == 1 and p_offset == 0xf000:
            filesz, memsz = struct.unpack_from('<QQ', d, ph + 32)
            assert filesz == memsz == 0x156d8 and p_flags == 5
            struct.pack_into('<QQ', d, ph + 32, CAVE + 16 - 0xf000, CAVE + 16 - 0xf000)
            break
    else:
        sys.exit('R+X segment not found')

    open(dst, 'wb').write(d)
    print('patched', dst, hashlib.md5(d).hexdigest())


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
