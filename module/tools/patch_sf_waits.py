#!/usr/bin/env python3
"""Stop SurfaceFlinger from waiting for OPPO display HALs absent on pipa.

Usage: python3 -I patch_sf_waits.py in/surfaceflinger out/surfaceflinger

Resolve the PLT through .rela.plt and its dynamic symbols. Decode BL targets
in .text. Identify each service through the next typed AIDL fromBinder call.
This also identifies service names held in C++ strings, such as IMixLut3D and
IIris. Change only IDisplayColorFeature (two calls), IMixLut3D and IIris.
Keep the IComposer and IIrisFeature waits. Stop if any call count or type changes.
The existing code handles null binders. C.06 hashes are a regression check.
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

STOCK_MD5 = '405ff9632578c15c6b36ef795cb0853b'
PATCHED_MD5 = '011603bbe0bb51cd6680a6a50f95c938'
BINDER_SUFFIX = '10fromBinderERKN3ndk10SpAIBinderE'
# These symbol prefixes encode the same interfaces as the service-name strings.
INTERFACES = {
    '_ZN4aidl6vendor5oplus8hardware19displaycolorfeature20IDisplayColorFeature': (2, True),
    '_ZN4aidl6vendor5oplus8hardware7display8MixLut3D9IMixLut3D': (1, True),
    '_ZN4aidl6vendor10pixelworks8hardware7display5IIris': (1, True),
    '_ZN4aidl6vendor10pixelworks8hardware7feature12IIrisFeature': (1, False),
    '_ZN4aidl7android8hardware8graphics9composer39IComposer': (1, False),
}


def find_sites(elf):
    wait = elf.plt_address('AServiceManager_waitForService')
    check = elf.plt_address('AServiceManager_checkService')
    text = elf.section('.text')
    converters = {elf.plt_address(name + BINDER_SUFFIX): name for name in INTERFACES}
    waits = [pc for pc, word in elf.code(text)
             if branch_target(word, pc, True) == wait]
    require(len(waits) == 6, 'waitForService: expected 6 BL sites, found %d' % len(waits))
    found = {name: [] for name in INTERFACES}
    for pc in waits:
        converter = None
        # No intervening calls or control flow may separate the wait from its conversion.
        for pos in range(pc + 4, min(pc + 36, text['addr'] + text['size']), 4):
            word = elf.word(pos)
            target = branch_target(word, pos, True)
            if target is not None:
                converter = converters.get(target)
                break
            if (word & 0x7c000000 == 0x14000000 or
                    word & 0xff000010 == 0x54000000 or
                    word & 0x7e000000 in (0x34000000, 0x36000000) or
                    word & 0xfe000000 == 0xd6000000):
                break
        require(converter is not None,
                'waitForService at 0x%x: no recognized following fromBinder call' % pc)
        found[converter].append(pc)
    sites = []
    for name, (count, patch) in INTERFACES.items():
        require(len(found[name]) == count,
                '%s: expected %d wait sites, found %d' % (name, count, len(found[name])))
        if patch:
            sites.extend(found[name])
    return sorted(sites), check


def main(src, dst):
    data = bytearray(Path(src).read_bytes())
    original_md5 = hashlib.md5(data).hexdigest()
    elf = ELF(data)
    sites, check = find_sites(elf)
    for pc in sites:
        off = elf.fileoff(pc)
        data[off:off + 4] = branch(pc, check, True)
    result_md5 = hashlib.md5(data).hexdigest()
    require(original_md5 != STOCK_MD5 or result_md5 == PATCHED_MD5,
            'C.06 regression: output md5 %s, expected %s' % (result_md5, PATCHED_MD5))
    Path(dst).write_bytes(data)
    print('patched %d waitForService -> checkService sites (%s); md5 %s; wrote %s' %
          (len(sites), ', '.join('0x%x' % pc for pc in sites), result_md5, dst))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        main(sys.argv[1], sys.argv[2])
    except (ValueError, OSError, struct.error) as exc:
        sys.exit('surfaceflinger: ' + str(exc))
