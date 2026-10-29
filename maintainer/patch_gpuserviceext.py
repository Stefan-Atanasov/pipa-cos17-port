#!/usr/bin/env python3
"""Null-guard OPPO's system_ext/lib64/libgpuserviceextimpl.so.

Usage: python3 maintainer/patch_gpuserviceext.py <in.so> <out.so>

GpuServiceExtImpl::onTransact forwards six binder codes to the PreCacheService
at this+0x68 before GpuMem::initialize() sets it. Return 0 if that pointer is null.
Find each forwarding block by its instructions and the resolved PreCacheService
PLT target. Require exactly one match per block in the exported onTransact.
Five tail calls drop a redundant ldp x20,x19 to make room for cbz.
The load call uses a 16-byte stub in verified padding after the executable LOAD.
All addresses come from ELF metadata or instruction patterns. C.06 hashes check
that the result stays byte-identical to the original patch.
"""

import hashlib
import struct
import sys
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def one(items, description):
    require(len(items) == 1, '%s: expected exactly one match, found %d' %
            (description, len(items)))
    return items[0]


def signed(value, bits):
    return (value ^ (1 << (bits - 1))) - (1 << (bits - 1))


def branch_target(word, pc, link=False):
    if word & 0xfc000000 == (0x94000000 if link else 0x14000000):
        return pc + signed(word & 0x3ffffff, 26) * 4
    return None


def branch(pc, target, link=False):
    delta = target - pc
    require(delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27),
            'branch out of range: 0x%x -> 0x%x' % (pc, target))
    return struct.pack('<I', (0x94000000 if link else 0x14000000) |
                       ((delta >> 2) & 0x3ffffff))


class ELF:
    """Read ELF64 LE AArch64 sections, symbols and standard AArch64 PLT stubs."""

    def __init__(self, data):
        self.data = data
        require(data[:7] == b'\x7fELF\x02\x01\x01', 'expected ELF64 little-endian input')
        require(self.unpack('<H', 18)[0] == 183, 'expected AArch64 input')
        phoff, shoff = self.unpack('<QQ', 32)
        phentsize, phnum, shentsize, shnum, shstrndx = self.unpack('<HHHHH', 54)
        require(phentsize == 56 and shentsize == 64 and shnum > 0,
                'unsupported ELF header tables')
        self.sh_table = (shoff, shoff + shentsize * shnum)
        raw = [self.unpack('<IIQQQQIIQQ', shoff + i * shentsize)
               for i in range(shnum)]
        require(shstrndx < shnum, 'invalid section name table')
        names = self.slice(raw[shstrndx][4], raw[shstrndx][5])
        self.sections = []
        for fields in raw:
            name, kind, flags, addr, off, size, link, info, align, entsize = fields
            if kind != 8:  # SHT_NOBITS has no bytes in the file.
                self.slice(off, size)
            self.sections.append(dict(name=self.string(names, name), type=kind,
                                      flags=flags, addr=addr, off=off, size=size,
                                      link=link, entsize=entsize))
        self.loads = []
        for i in range(phnum):
            off = phoff + i * phentsize
            kind, flags, fileoff, va, pa, filesz, memsz, align = self.unpack('<IIQQQQQQ', off)
            if kind == 1:
                self.slice(fileoff, filesz)
                require(filesz <= memsz, 'invalid PT_LOAD sizes')
                self.loads.append(dict(ph=off, flags=flags, off=fileoff, addr=va,
                                       size=filesz, memsz=memsz))
        self.plt = self.read_plt()

    def slice(self, off, size):
        require(0 <= off <= len(self.data) and 0 <= size <= len(self.data) - off,
                'ELF range outside file: 0x%x + 0x%x' % (off, size))
        return self.data[off:off + size]

    def unpack(self, fmt, off):
        return struct.unpack(fmt, self.slice(off, struct.calcsize(fmt)))

    @staticmethod
    def string(table, off):
        require(0 <= off < len(table), 'invalid ELF string offset')
        end = table.find(b'\0', off)
        require(end >= 0, 'unterminated ELF string')
        return bytes(table[off:end]).decode('ascii')

    def section(self, name):
        return one([s for s in self.sections if s['name'] == name], name)

    def symbols(self, section):
        require(section['type'] == 11 and section['entsize'] == 24 and
                section['size'] % 24 == 0, 'invalid dynamic symbol table')
        require(section['link'] < len(self.sections), 'invalid symbol string table link')
        strings = self.sections[section['link']]
        table = self.slice(strings['off'], strings['size'])
        result = []
        for off in range(section['off'], section['off'] + section['size'], 24):
            name, info, other, shndx, value, size = self.unpack('<IBBHQQ', off)
            result.append(dict(name=self.string(table, name), addr=value,
                               size=size, shndx=shndx, info=info))
        return result

    def fileoff(self, va, size=4):
        load = one([p for p in self.loads
                    if p['addr'] <= va and va + size <= p['addr'] + p['size']],
                   'file-backed mapping for 0x%x' % va)
        return load['off'] + va - load['addr']

    def word(self, va):
        return self.unpack('<I', self.fileoff(va))[0]

    def code(self, section):
        require(section['flags'] & 4 and section['addr'] % 4 == 0 and
                section['size'] % 4 == 0, 'invalid executable section')
        for off in range(section['off'], section['off'] + section['size'], 4):
            yield section['addr'] + off - section['off'], self.unpack('<I', off)[0]

    def read_plt(self):
        rela = self.section('.rela.plt')
        require(rela['type'] == 4 and rela['entsize'] == 24 and
                rela['size'] % 24 == 0 and rela['link'] < len(self.sections),
                'invalid .rela.plt')
        symbols = self.symbols(self.sections[rela['link']])
        slots = {}
        for off in range(rela['off'], rela['off'] + rela['size'], 24):
            got, info, addend = self.unpack('<QQq', off)
            require(info & 0xffffffff == 1026 and info >> 32 < len(symbols),
                    'unsupported PLT relocation')
            require(got not in slots, 'duplicate PLT relocation')
            slots[got] = symbols[info >> 32]['name']
        result = {}
        section = self.section('.plt')
        for pc, insn in self.code(section):
            if pc + 16 > section['addr'] + section['size']:
                continue
            # adrp x16, page; ldr x17,[x16,#slot]; add x16,x16,#slot; br x17.
            if insn & 0x9f00001f != 0x90000010:
                continue
            ldr, add, br = (self.word(pc + n) for n in (4, 8, 12))
            if ldr & 0xffc003ff != 0xf9400211 or br != 0xd61f0220:
                continue
            disp = signed(((insn >> 5) & 0x7ffff) << 2 | ((insn >> 29) & 3), 21)
            slot = ((pc & ~0xfff) + (disp << 12)) + ((ldr >> 10) & 0xfff) * 8
            if slot not in slots or add != 0x91000210 | (((ldr >> 10) & 0xfff) * 8 << 10):
                continue
            entry = pc
            if pc > section['addr'] and self.word(pc - 4) in (0xd503245f, 0xd50324df):
                entry -= 4  # Include a BTI landing instruction when present.
            result.setdefault(slots[slot], []).append(entry)
        return result

    def plt_address(self, name):
        return one(self.plt.get(name, []), name + '@plt')

SRC_MD5 = 'f58c0678f969b718a91398495a5358c9'
PATCHED_MD5 = '79be7f1b1c4eb632a2a14614189775dc'
ON_TRANSACT = '_ZN7android17GpuServiceExtImpl10onTransactEjRKNS_6ParcelEPS1_j'
LDR_X0_68 = bytes.fromhex('003440f9')  # ldr x0,[x0,#0x68]
LDP_X20_X19 = bytes.fromhex('f44f43a9')
EPILOGUE = bytes.fromhex('fd7b42a9ff030191bf2303d5')
RET0_PATTERN = bytes.fromhex('e0031f2a') + LDP_X20_X19 + EPILOGUE + bytes.fromhex('c0035fd6')
MOV_TWO = bytes.fromhex('e10302aae20303aa')  # mov x1,x2; mov x2,x3
MOV_ONE = bytes.fromhex('e10303aa')  # mov x1,x3
TAILS = (
    ('10getAppInfoERKNS_6ParcelEPS1_', MOV_TWO),
    ('15queryWarmupGateERKNS_6ParcelEPS1_', MOV_TWO),
    ('16notifyWarmupDoneERKNS_6ParcelEPS1_', MOV_TWO),
    ('19writeAllRePathInfosEPNS_6ParcelE', MOV_ONE),
    ('19handleRuntimeConfigERKNS_6ParcelEPS1_', MOV_TWO),
)


def cbz_x0(pc, target):
    delta = target - pc
    require(delta % 4 == 0 and -(1 << 20) <= delta < (1 << 20),
            'cbz out of range: 0x%x -> 0x%x' % (pc, target))
    return struct.pack('<I', 0xb4000000 | (((delta >> 2) & 0x7ffff) << 5))


def find_sites(elf):
    symbol = one([s for s in elf.symbols(elf.section('.dynsym'))
                  if s['name'] == ON_TRANSACT and s['shndx'] != 0 and
                  s['info'] & 15 == 2 and s['size'] > 0], 'onTransact function')
    start, size = symbol['addr'], symbol['size']
    off = elf.fileoff(start, size)
    text = elf.section('.text')
    require(text['addr'] <= start and start + size <= text['addr'] + text['size'],
            'onTransact is outside .text')
    code = bytes(elf.slice(off, size))

    def matches(pattern):
        return [start + i for i in range(0, len(code) - len(pattern) + 1, 4)
                if code[i:i + len(pattern)] == pattern]

    ret0 = one(matches(RET0_PATTERN), 'return-zero epilogue')
    tails = []
    for suffix, movs in TAILS:
        name = '_ZN7android15PreCacheService' + suffix
        target = elf.plt_address(name)
        pattern = LDR_X0_68 + movs + LDP_X20_X19 + EPILOGUE
        sites = [pc for pc in matches(pattern)
                 if pc + len(pattern) + 4 <= start + size and
                 branch_target(elf.word(pc + len(pattern)), pc + len(pattern)) == target]
        tails.append((one(sites, name + ' forwarding block'), movs))
    load_plt = elf.plt_address('_ZN7android15PreCacheService4loadEv')
    load = one([pc for pc in matches(LDR_X0_68)
                if pc + 8 <= start + size and
                branch_target(elf.word(pc + 4), pc + 4, True) == load_plt and
                pc + 8 == ret0], 'PreCacheService::load forwarding block')
    require(len(matches(LDR_X0_68)) == 6,
            'onTransact: expected 6 PreCacheService pointer loads, found %d' %
            len(matches(LDR_X0_68)))
    return tails, load, ret0, load_plt


def find_cave(elf):
    plt = elf.section('.plt')
    segment = one([p for p in elf.loads if p['flags'] == 5 and
                   p['off'] <= plt['off'] and
                   plt['off'] + plt['size'] == p['off'] + p['size']],
                  'executable LOAD ending at .plt')
    require(segment['size'] == segment['memsz'],
            'executable LOAD has a zero-fill tail')
    end = segment['off'] + segment['size']
    cave = (end + 15) & ~15
    va = segment['addr'] + cave - segment['off']
    new_end = cave + 16
    # Keep the stub in the last mapped page. Do not change other segment permissions.
    require((segment['addr'] + segment['size'] - 1) // 4096 == (va + 15) // 4096,
            'no room for the stub in the last executable page')
    require(elf.slice(end, new_end - end) == bytes(new_end - end),
            'stub padding after executable LOAD is not zero')
    for section in elf.sections:
        if section['type'] != 8 and section['size']:
            require(new_end <= section['off'] or section['off'] + section['size'] <= end,
                    'stub would overwrite section ' + section['name'])
    lo, hi = elf.sh_table
    require(new_end <= lo or hi <= end, 'stub would overwrite section headers')
    for other in elf.loads:
        if other is segment:
            continue
        require(new_end <= other['off'] or other['off'] + other['size'] <= end,
                'stub overlaps another LOAD in the file')
        require(va + 16 <= other['addr'] or
                other['addr'] + other['memsz'] <= va,
                'stub overlaps another LOAD in memory')
    return segment, cave, va


def main(src, dst):
    data = bytearray(Path(src).read_bytes())
    original_md5 = hashlib.md5(data).hexdigest()
    elf = ELF(data)
    tails, load, ret0, load_plt = find_sites(elf)
    segment, cave_off, cave = find_cave(elf)
    # Validate all branch encodings before changing any bytes.
    edits = []
    for pc, movs in tails:
        edits.append((elf.fileoff(pc + 4), cbz_x0(pc + 4, ret0) + movs))
    edits.append((elf.fileoff(load), branch(load, cave)))
    edits.append((cave_off, LDR_X0_68 + cbz_x0(cave + 4, ret0) +
                  branch(cave + 8, load_plt, True) + branch(cave + 12, ret0)))
    for off, replacement in edits:
        data[off:off + len(replacement)] = replacement
    new_size = cave_off + 16 - segment['off']
    struct.pack_into('<QQ', data, segment['ph'] + 32, new_size, new_size)
    result_md5 = hashlib.md5(data).hexdigest()
    require(original_md5 != SRC_MD5 or result_md5 == PATCHED_MD5,
            'C.06 regression: output md5 %s, expected %s' % (result_md5, PATCHED_MD5))
    Path(dst).write_bytes(data)
    print('patched 6 null guards (%s); stub 0x%x; md5 %s; wrote %s' %
          (', '.join('0x%x' % pc for pc in sorted([pc for pc, _ in tails] + [load])),
           cave, result_md5, dst))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        main(sys.argv[1], sys.argv[2])
    except (ValueError, OSError, struct.error) as exc:
        sys.exit('gpuservice extension: ' + str(exc))
