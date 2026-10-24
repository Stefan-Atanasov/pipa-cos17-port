#!/usr/bin/env python3
"""Patch OPPO IPeManager so that the Xiaomi pen gets ColorOS's own live-alert (fluid cloud) battery card.

IPeManager shows the card from k0.B0(level), but only after its OPPO BLE GATT link to the pen works. The Xiaomi pen
does not have that link. This patch changes the end of k0.h0(present, mac) (the "new pen present" branch, which
starts the BLE link with k0.c(...)) to:

    level = Settings.Global.getInt(mContext.getContentResolver(), "ipe_pencil_battery_level", -1)
    B0(level)          # shows the fluid-cloud battery card (level < 0: "connected" card without battery)
    return

Two more 4-byte branch edits in h0 (if-* -> goto/16 with the same offset):
  P1  "if (mConnectTask.mPresent == present) return": without it only the first present=1 after a present=0 shows the
      card; pipa_port sends present=1 on each dock and undock.
  P2  "if (mConnectTask.state == 2 && !d0(mac)) B0(k0.L)": k0.L is the OPPO BLE battery reading (never set for the
      Xiaomi pen), so this branch also goes to the new code above.

pipa_port writes ipe_pencil_battery_level and sends the PENCIL_STATUS_CHANGE intent (present 1/0).
Only dex bytes inside h0 change; the final log + return-void stays at its offset, so no branch moves.

Usage (plain python3, no other module):
    patch_ipemanager.py <IPeManager.apk in> <IPeManager.apk out>
The dex is patched in place with the same size inside the original APK (classes2.dex is stored, not deflated); only
the CRC32 in the local and central zip headers changes. OPPO's signature block stays: the APK is signed with the
platform key, and Android does not verify APKs on system partitions at boot (it only reads the certificate), so the
app keeps its platform identity and permissions. Do not re-sign it.
Prints the offsets it changed. Stops if the code does not look exactly as expected (other IPeManager version).
"""
import hashlib
import io
import struct
import sys
import zipfile
import zlib

K0 = 'Lcom/oplus/ipemanager/btadsorb/ble/k0;'


def uleb(b, o):
    r = s = 0
    while True:
        x = b[o]; o += 1
        r |= (x & 0x7f) << s; s += 7
        if x < 0x80:
            return r, o


class Dex:
    def __init__(self, data):
        self.b = bytearray(data)
        assert self.b[:4] == b'dex\n', 'not a dex file'
        h = struct.unpack_from('<20I', self.b, 0x38)
        (self.str_n, self.str_o, self.typ_n, self.typ_o, self.pro_n, self.pro_o, self.fld_n, self.fld_o,
         self.met_n, self.met_o, self.cls_n, self.cls_o) = h[0:12]

    def string(self, i):
        off = struct.unpack_from('<I', self.b, self.str_o + 4 * i)[0]
        _, o = uleb(self.b, off)
        e = self.b.index(0, o)
        return bytes(self.b[o:e]).decode('utf-8', 'replace')

    def type(self, i):
        return self.string(struct.unpack_from('<I', self.b, self.typ_o + 4 * i)[0])

    def proto(self, i):
        _, ret, poff = struct.unpack_from('<3I', self.b, self.pro_o + 12 * i)
        params = []
        if poff:
            n = struct.unpack_from('<I', self.b, poff)[0]
            params = [self.type(struct.unpack_from('<H', self.b, poff + 4 + 2 * k)[0]) for k in range(n)]
        return '(' + ''.join(params) + ')' + self.type(ret)

    def find_string(self, s):
        for i in range(self.str_n):
            if self.string(i) == s:
                return i
        raise SystemExit(f'string not in dex: {s}')

    def find_method(self, cls, name, sig):
        for i in range(self.met_n):
            c, p, n = struct.unpack_from('<HHI', self.b, self.met_o + 8 * i)
            if self.type(c) == cls and self.string(n) == name and self.proto(p) == sig:
                return i
        raise SystemExit(f'method not in dex: {cls}->{name}{sig}')

    def find_field(self, cls, name):
        for i in range(self.fld_n):
            c, t, n = struct.unpack_from('<HHI', self.b, self.fld_o + 8 * i)
            if self.type(c) == cls and self.string(n) == name:
                return i
        raise SystemExit(f'field not in dex: {cls}->{name}')

    def code_off(self, cls, name, sig):
        mid = self.find_method(cls, name, sig)
        for i in range(self.cls_n):
            cidx, _, _, _, _, _, cdata, _ = struct.unpack_from('<8I', self.b, self.cls_o + 32 * i)
            if self.type(cidx) != cls:
                continue
            o = cdata
            sf, o = uleb(self.b, o); inf, o = uleb(self.b, o); dm, o = uleb(self.b, o); vm, o = uleb(self.b, o)
            for _ in range(sf + inf):
                _, o = uleb(self.b, o); _, o = uleb(self.b, o)
            for count in (dm, vm):          # the method index diff restarts for the virtual list
                m = 0
                for _ in range(count):
                    d, o = uleb(self.b, o); m += d
                    _, o = uleb(self.b, o); co, o = uleb(self.b, o)
                    if m == mid:
                        return co
        raise SystemExit(f'code not found: {cls}->{name}{sig}')

    def fix_header(self):
        self.b[12:32] = hashlib.sha1(self.b[32:]).digest()
        struct.pack_into('<I', self.b, 8, zlib.adler32(bytes(self.b[12:])) & 0xffffffff)


def ins_35c(op, regs, idx):
    r = list(regs) + [0] * (5 - len(regs))
    return bytes([op, (len(regs) << 4) | r[4]]) + struct.pack('<HH', idx, r[0] | r[1] << 4 | r[2] << 8 | r[3] << 12)


def patch_dex(data):
    d = Dex(data)
    m_c = d.find_method(K0, 'c', '(Ljava/lang/Integer;Ljava/lang/String;)V')
    m_b0 = d.find_method(K0, 'B0', '(I)V')
    m_cr = d.find_method('Landroid/content/Context;', 'getContentResolver', '()Landroid/content/ContentResolver;')
    m_get = d.find_method('Landroid/provider/Settings$Global;', 'getInt',
                          '(Landroid/content/ContentResolver;Ljava/lang/String;I)I')
    f_ctx = d.find_field('Lcom/oplus/ipemanager/btadsorb/ble/g;', 'a')
    s_mac = d.find_string('ipe_pencil_mac_addr')
    s_bat = d.find_string('ipe_pencil_battery_level')
    s_pres = d.find_string('pencilNodeChange mConnectTask?.mPresent = ')
    m_d0 = d.find_method(K0, 'd0', '(Ljava/lang/String;)Z')
    assert s_bat <= 0xffff and s_mac <= 0xffff, 'string index needs const-string/jumbo'

    co = d.code_off(K0, 'h0', '(Ljava/lang/String;Ljava/lang/String;)V')
    regs, ins_n, outs, tries, _, insns = struct.unpack_from('<4HII', d.b, co)
    assert regs >= 10 and outs >= 3, (regs, outs)
    start = co + 16
    code = d.b[start:start + 2 * insns]

    # start of the region: "const-string v0, "ipe_pencil_mac_addr"" (1a 00 <idx>)
    pat = bytes([0x1a, 0x00]) + struct.pack('<H', s_mac)
    a = code.find(pat)
    assert a > 0 and code.find(pat, a + 1) < 0, 'anchor const-string not found exactly once'
    # end of the region: the call k0.c(Integer, String) on {v7, v8, v9} + return-void
    call_c = ins_35c(0x6e, [7, 8, 9], m_c) + b'\x0e\x00'
    e = code.find(call_c, a)
    assert e > a and code.find(call_c, e + 1) < 0, 'k0.c call not found exactly once'
    end = e + len(call_c)
    if tries:
        print('note: method has', tries, 'try blocks (region keeps its size, so they stay valid)')

    new = (bytes([0x54, 0x70]) + struct.pack('<H', f_ctx)          # iget-object v0, v7, g->a (Context)
           + ins_35c(0x6e, [0], m_cr)                               # invoke-virtual {v0}, getContentResolver()
           + b'\x0c\x00'                                            # move-result-object v0
           + bytes([0x1a, 0x01]) + struct.pack('<H', s_bat)         # const-string v1, "ipe_pencil_battery_level"
           + b'\x12\xf2'                                            # const/4 v2, -1
           + ins_35c(0x71, [0, 1, 2], m_get)                        # invoke-static {v0, v1, v2}, Settings$Global->getInt
           + b'\x0a\x08'                                            # move-result v8
           + ins_35c(0x6e, [7, 8], m_b0)                            # invoke-virtual {v7, v8}, k0->B0(I)V
           + b'\x0e\x00')                                           # return-void
    assert len(new) <= end - a, (len(new), end - a)
    new += b'\x00\x00' * ((end - a - len(new)) // 2)              # nop
    d.b[start + a:start + end] = new

    def once(pat, what):
        i = code.find(pat)
        assert i >= 0 and code.find(pat, i + 1) < 0 and i < a, f'{what}: pattern not found exactly once'
        return i
    # P1: const-string v6, "...mPresent = " ; if-eqz v2, +6  ->  goto/16 +6
    p1 = once(bytes([0x1a, 0x06]) + struct.pack('<H', s_pres) + bytes([0x38, 0x02, 0x06, 0x00]), 'P1') + 4
    d.b[start + p1:start + p1 + 4] = bytes([0x29, 0x00, 0x06, 0x00])
    # P2: if-ne v0, v4, +0xe ; invoke-virtual {v7, v9}, k0->d0  ->  goto/16 +0xe (to the new code)
    p2 = once(bytes([0x33, 0x40, 0x0e, 0x00]) + ins_35c(0x6e, [7, 9], m_d0), 'P2')
    assert p2 + 2 * 0x0e == a, 'P2 target is not the new code'
    d.b[start + p2:start + p2 + 4] = bytes([0x29, 0x00, 0x0e, 0x00])
    print(f'P1 at 0x{start + p1:x}, P2 at 0x{start + p2:x}')
    d.fix_header()
    print(f'h0 code at 0x{co:x}: replaced 0x{start + a:x}..0x{start + end:x} ({end - a} bytes, new code {len(new) - (end - a - 34)})')
    return bytes(d.b)


def main(src, dst):
    apk = bytearray(open(src, 'rb').read())
    z = zipfile.ZipFile(io.BytesIO(apk))
    info = None
    for i in z.infolist():
        if i.filename.endswith('.dex') and i.compress_type == 0:
            if K0[1:-1].encode() in z.read(i.filename):
                info = i
    assert info, 'no stored dex with k0'
    lh = info.header_offset
    assert apk[lh:lh + 4] == b'PK\x03\x04'
    n, x = struct.unpack_from('<HH', apk, lh + 26)
    off = lh + 30 + n + x
    old = bytes(apk[off:off + info.file_size])
    new = patch_dex(old)
    assert len(new) == len(old)
    apk[off:off + len(new)] = new
    crc = zlib.crc32(new) & 0xffffffff
    struct.pack_into('<I', apk, lh + 14, crc)
    eocd = apk.rfind(b'PK\x05\x06')
    cd_off = struct.unpack_from('<I', apk, eocd + 16)[0]
    p = cd_off
    while apk[p:p + 4] == b'PK\x01\x02':
        fn, ex, cm = struct.unpack_from('<HHH', apk, p + 28)
        if struct.unpack_from('<I', apk, p + 42)[0] == lh:
            struct.pack_into('<I', apk, p + 16, crc)
            break
        p += 46 + fn + ex + cm
    else:
        raise SystemExit('central directory entry not found')
    open(dst, 'wb').write(apk)
    print(f'{info.filename}: patched in place, crc32 {crc:08x}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
