#!/usr/bin/env python3
"""odm_closure.py: library closure and symbol check of the ODM partition of a port tree (Python stdlib only).

Questions it answers (static; it does not run anything):
  1. Does every ELF in /odm (and every binary that an init rc file starts from /odm) find all its DT_NEEDED
     libraries on the paths that the Android linker would use for it?
  2. Does every undefined (strong) dynamic symbol of those ELF files have a definition in the libraries that the
     process loads? This catches an ABI mismatch between libraries of two builds (C.05 against C.06).

Usage:
  python3 odm_closure.py --tree port-work/pt4/tree                       full check, exit 1 on a problem
  python3 odm_closure.py --tree T --odm EXTRACTED_ODM_DIR                use another odm (baseline from odm.img)
  python3 odm_closure.py --tree T --assume-no-private                    ignore LD_LIBRARY_PATH of the rc files
  python3 odm_closure.py --tree T --abi-diff OLD_ODM_DIR                 export diff of each changed library
Options: --no-symbols, --strict (orphan ELF files also fail), -v, --top N, --apex-cache DIR.

Layout: --tree has the partition folders of port.sh: system (system-as-root, so /system is system/system),
system_ext, product, vendor, odm. The virtual paths /system /system_ext /product /vendor /odm /apex/<name>
map to them. Absolute symlinks are followed inside this map and never leave it.

Resolution order for a DT_NEEDED name (the order of the task, then a namespace check):
  1. private dirs: LD_LIBRARY_PATH from the `setenv` line of the service that starts the process
  2. /odm/lib64 | /odm/lib      (lib64 for ELF64, lib for ELF32)
  3. /vendor/lib64 | /vendor/lib
  4. /system/lib64, /system_ext/lib64, /product/lib64   (a vendor-namespace process can load from these only
     the libraries on the LLNDK list /system/etc/llndk.libraries.txt, or the public list; any other hit is
     reported as NOT-VISIBLE and counts as unresolved)
  5. the APEX libraries that exist in every namespace: com.android.runtime (libc, libm, libdl, ...) and every
     other APEX that is extracted next to it. The .apex files in /system/apex and /system_ext/apex are
     unpacked (zip + fsck.erofs or debugfs) into the cache dir. If that fails, the bionic names and the LLNDK
     names are accepted by name only (marked "name-only"; no symbol check for them).
"""
import argparse
import collections
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

# ---------------------------------------------------------------------------------------------- ELF parser

PT_LOAD, PT_DYNAMIC = 1, 2
DT_NULL, DT_NEEDED, DT_HASH, DT_STRTAB, DT_SYMTAB, DT_STRSZ, DT_SONAME = 0, 1, 4, 5, 6, 10, 14
DT_RPATH, DT_RUNPATH, DT_GNU_HASH = 15, 29, 0x6FFFFEF5
SHT_DYNSYM = 11
STB_GLOBAL, STB_WEAK, STB_GNU_UNIQUE = 1, 2, 10


class Elf:
    """DT_NEEDED, SONAME, RUNPATH and the dynamic symbols of one ELF file (little endian ELF32/ELF64)."""

    def __init__(self, path):
        self.path = path
        self.err = None
        self.bits = 0
        self.etype = 0
        self.machine = 0
        self.soname = None
        self.needed = []
        self.runpath = []
        self.undef = []          # strong undefined symbol names
        self.defs = set()        # exported (global/weak, not hidden) symbol names
        try:
            with open(path, 'rb') as f:
                self.data = f.read()
            self._parse()
        except (OSError, struct.error, ValueError, IndexError) as e:
            self.err = f'{type(e).__name__}: {e}'
        self.data = None

    def _cstr(self, off):
        end = self.data.index(b'\0', off)
        return self.data[off:end].decode('utf-8', 'replace')

    def _parse(self):
        d = self.data
        if d[:4] != b'\x7fELF':
            raise ValueError('not ELF')
        if d[5] != 1:
            raise ValueError('big endian ELF')
        self.bits = {1: 32, 2: 64}[d[4]]
        w = self.bits == 64
        self.etype, self.machine = struct.unpack_from('<HH', d, 16)
        if w:
            phoff, shoff = struct.unpack_from('<QQ', d, 32)
            phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from('<HHHHH', d, 54)
        else:
            phoff, shoff = struct.unpack_from('<II', d, 28)
            phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from('<HHHHH', d, 42)
        loads, dyn = [], None
        for i in range(phnum):
            o = phoff + i * phentsize
            if w:
                p_type, _fl, p_off, p_va, _pa, p_fs, p_ms, _al = struct.unpack_from('<IIQQQQQQ', d, o)
            else:
                p_type, p_off, p_va, _pa, p_fs, p_ms, _fl, _al = struct.unpack_from('<IIIIIIII', d, o)
            if p_type == PT_LOAD:
                loads.append((p_va, p_off, p_fs))
            elif p_type == PT_DYNAMIC:
                dyn = (p_off, p_fs)
        if dyn is None:
            return                                   # static executable or object: nothing to resolve

        def v2o(va):                                 # virtual address -> file offset
            for lva, loff, lfs in loads:
                if lva <= va < lva + lfs:
                    return va - lva + loff
            raise ValueError(f'address {va:#x} is in no PT_LOAD')

        tags = []
        esz = 16 if w else 8
        fmt = '<qQ' if w else '<iI'
        for o in range(dyn[0], dyn[0] + dyn[1], esz):
            t, v = struct.unpack_from(fmt, d, o)
            if t == DT_NULL:
                break
            tags.append((t, v))
        tv = dict()
        for t, v in tags:
            tv.setdefault(t, v)
        strtab = v2o(tv[DT_STRTAB]) if DT_STRTAB in tv else None
        for t, v in tags:
            if strtab is None:
                break
            if t == DT_NEEDED:
                self.needed.append(self._cstr(strtab + v))
            elif t == DT_SONAME:
                self.soname = self._cstr(strtab + v)
            elif t in (DT_RUNPATH, DT_RPATH):
                self.runpath += [x for x in self._cstr(strtab + v).split(':') if x]
        # dynamic symbols: section headers first, else DT_HASH / DT_GNU_HASH
        symoff = symcnt = stroff = None
        if shoff and shnum:
            for i in range(shnum):
                o = shoff + i * shentsize
                if w:
                    _n, sh_type, _f, _a, sh_off, sh_size, sh_link, _i, _al, sh_ent = struct.unpack_from('<IIQQQQIIQQ', d, o)
                else:
                    _n, sh_type, _f, _a, sh_off, sh_size, sh_link, _i, _al, sh_ent = struct.unpack_from('<IIIIIIIIII', d, o)
                if sh_type == SHT_DYNSYM and sh_ent:
                    symoff, symcnt = sh_off, sh_size // sh_ent
                    so = shoff + sh_link * shentsize
                    stroff = struct.unpack_from('<Q' if w else '<I', d, so + (24 if w else 16))[0]
                    break
        if symoff is None and DT_SYMTAB in tv and DT_STRTAB in tv:
            symoff, stroff = v2o(tv[DT_SYMTAB]), strtab
            if DT_HASH in tv:
                symcnt = struct.unpack_from('<II', d, v2o(tv[DT_HASH]))[1]
            elif DT_GNU_HASH in tv:
                symcnt = self._gnu_symcount(v2o(tv[DT_GNU_HASH]), w)
        if symoff is None or not symcnt:
            return
        ssz = 24 if w else 16
        for i in range(1, symcnt):
            o = symoff + i * ssz
            if w:
                st_name, st_info, st_other, st_shndx = struct.unpack_from('<IBBH', d, o)
            else:
                st_name, _val, _sz, st_info, st_other, st_shndx = struct.unpack_from('<IIIBBH', d, o)
            if not st_name:
                continue
            bind = st_info >> 4
            name = self._cstr(stroff + st_name)
            if st_shndx == 0:
                if bind == STB_GLOBAL or bind == STB_GNU_UNIQUE:
                    self.undef.append(name)
            elif bind in (STB_GLOBAL, STB_WEAK, STB_GNU_UNIQUE) and (st_other & 3) in (0, 3):
                self.defs.add(name)

    def _gnu_symcount(self, off, w):
        d = self.data
        nbuckets, symoffset, bloom_size, _shift = struct.unpack_from('<IIII', d, off)
        bloom_sz = 8 if w else 4
        bpos = off + 16 + bloom_size * bloom_sz
        buckets = struct.unpack_from(f'<{nbuckets}I', d, bpos)
        last = max(buckets) if buckets else 0
        if last < symoffset:
            return symoffset
        cpos = bpos + nbuckets * 4
        while True:
            h = struct.unpack_from('<I', d, cpos + (last - symoffset) * 4)[0]
            if h & 1:
                return last + 1
            last += 1


# ---------------------------------------------------------------------------------------------- virtual root

class VRoot:
    """Maps /system /system_ext /product /vendor /odm /apex/<n> to folders and follows symlinks inside the map."""

    def __init__(self, tree, odm=None, apex_cache=None):
        self.tree = tree
        sysroot = os.path.join(tree, 'system')
        # system-as-root: <tree>/system/system is /system. A flat system folder also works.
        self.system = os.path.join(sysroot, 'system') if os.path.isdir(os.path.join(sysroot, 'system')) else sysroot
        self.map = {
            '/system': self.system,
            '/system_ext': os.path.join(tree, 'system_ext'),
            '/product': os.path.join(tree, 'product'),
            '/vendor': os.path.join(tree, 'vendor'),
            '/odm': odm or os.path.join(tree, 'odm'),
        }
        self.apex = {}                    # name -> folder with the unpacked payload
        self.apex_cache = apex_cache
        self.apex_note = ''

    def real(self, vpath, _depth=0):
        """Virtual path -> real path (follows symlinks inside the map), or None."""
        if _depth > 24:
            return None
        parts = [p for p in vpath.split('/') if p]
        if not parts:
            return None
        if parts[0] == 'apex':
            if len(parts) < 2 or parts[1] not in self.apex:
                return None
            cur, rest = self.apex[parts[1]], parts[2:]
            vcur = '/apex/' + parts[1]
        else:
            base = '/' + parts[0]
            if base not in self.map:
                return None
            cur, rest = self.map[base], parts[1:]
            vcur = base
        for i, p in enumerate(rest):
            if p == '..':
                cur = os.path.dirname(cur)
                vcur = os.path.dirname(vcur)
                continue
            nxt = os.path.join(cur, p)
            if os.path.islink(nxt):
                tgt = os.readlink(nxt)
                tv = tgt if tgt.startswith('/') else os.path.normpath(os.path.join(vcur, tgt))
                tail = '/'.join(rest[i + 1:])
                return self.real(tv + ('/' + tail if tail else ''), _depth + 1)
            cur, vcur = nxt, vcur + '/' + p
        return cur if os.path.exists(cur) else None

    def setup_apex(self):
        """Unpack the .apex files in /system/apex and /system_ext/apex into the cache (best effort)."""
        found = []
        for v in ('/system/apex', '/system_ext/apex', '/vendor/apex', '/product/apex'):
            r = self.real(v)
            if r and os.path.isdir(r):
                found += [os.path.join(r, f) for f in sorted(os.listdir(r)) if f.endswith(('.apex', '.capex'))]
        if not found:
            self.apex_note = 'no .apex files in the tree'
            return
        cache = self.apex_cache or tempfile.mkdtemp(prefix='odm_closure_apex_')
        os.makedirs(cache, exist_ok=True)
        # only the APEX that carry shared libraries need unpacking; the runtime APEX (bionic) first
        want = [f for f in found if re.search(r'com\.android\.(runtime|vndk|i18n)', os.path.basename(f))]
        for f in want:
            name = re.sub(r'\.(c?apex)$', '', os.path.basename(f))
            dst = os.path.join(cache, name)
            if not os.path.isdir(dst):
                if not self._unpack(f, dst, cache):
                    continue
            self.apex[name] = dst
        if not any(n.startswith('com.android.runtime') for n in self.apex):
            self.apex_note = 'runtime APEX not unpacked (bionic checked by name only)'

    @staticmethod
    def _unpack(apex, dst, cache):
        try:
            with zipfile.ZipFile(apex) as z:
                if 'apex_payload.img' not in z.namelist():
                    return False                       # .capex wraps another apex; not handled
                img = os.path.join(cache, os.path.basename(dst) + '.img')
                with z.open('apex_payload.img') as src, open(img, 'wb') as out:
                    shutil.copyfileobj(src, out)
        except (OSError, zipfile.BadZipFile):
            return False
        with open(img, 'rb') as f:
            f.seek(1024)
            m = f.read(4)
        ok = False
        if m == b'\xe2\xe1\xf5\xe0' and shutil.which('fsck.erofs'):
            ok = subprocess.run(['fsck.erofs', f'--extract={dst}', img], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL).returncode == 0
        elif shutil.which('debugfs'):
            ok = subprocess.run(['debugfs', '-R', f'rdump / {dst}', img], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL).returncode == 0
            if ok and not os.path.isdir(dst):
                ok = False
        os.unlink(img)
        return ok


# ---------------------------------------------------------------------------------------------- rc parsing

class Service:
    def __init__(self, name, argv, rcfile):
        self.name, self.argv, self.rc = name, argv, rcfile
        self.env = {}
        self.disabled = False

    @property
    def exe(self):
        return self.argv[0]

    @property
    def ld_path(self):
        return [p for p in self.env.get('LD_LIBRARY_PATH', '').split(':') if p]

    @property
    def dlopen_args(self):
        return [a for a in self.argv[1:] if a.endswith('.so') and a.startswith('/')]


def parse_rc(real_path, vpath):
    """Services of one rc file. Returns a list of Service."""
    try:
        text = open(real_path, encoding='utf-8', errors='replace').read()
    except OSError:
        return []
    text = text.replace('\\\n', ' ')
    out, cur = [], None
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        tok = s.split()
        if tok[0] == 'service' and len(tok) >= 3:
            cur = Service(tok[1], tok[2:], vpath)
            out.append(cur)
        elif tok[0] in ('on', 'import'):
            cur = None
        elif cur is not None:
            if tok[0] == 'setenv' and len(tok) >= 3:
                cur.env[tok[1]] = tok[2]
            elif tok[0] == 'disabled':
                cur.disabled = True
    return out


def collect_services(vr):
    svcs = []
    for base in ('/odm', '/vendor', '/system_ext', '/system', '/product'):
        d = vr.real(base + '/etc/init')
        if d and os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.endswith('.rc'):
                    svcs += parse_rc(os.path.join(d, f), f'{base}/etc/init/{f}')
    return svcs


# ---------------------------------------------------------------------------------------------- resolver

class Checker:
    def __init__(self, vr, assume_no_private=False):
        self.vr = vr
        self.no_private = assume_no_private
        self.cache = {}
        self.allowed_sys = self._read_lists()
        self.bionic = {'libc.so', 'libm.so', 'libdl.so', 'ld-android.so', 'libdl_android.so'}

    def _read_lists(self):
        names = set()
        for rel in ('/system/etc/llndk.libraries.txt', '/system/etc/public.libraries.txt',
                    '/system/etc/vndksp.libraries.txt', '/system/etc/vndkcore.libraries.txt'):
            r = self.vr.real(rel)
            if r:
                for line in open(r, encoding='utf-8', errors='replace'):
                    w = line.split()
                    if w and not w[0].startswith('#') and w[0].endswith('.so'):
                        names.add(w[0])
        return names

    def elf(self, real):
        real = os.path.realpath(real)
        e = self.cache.get(real)
        if e is None:
            e = self.cache[real] = Elf(real)
        return e

    def std_dirs(self, bits):
        lib = 'lib64' if bits == 64 else 'lib'
        return [('odm', f'/odm/{lib}'), ('vendor', f'/vendor/{lib}'), ('system', f'/system/{lib}'),
                ('system_ext', f'/system_ext/{lib}'), ('product', f'/product/{lib}')]

    def resolve(self, name, bits, private):
        """-> (vpath, real, kind) or (None, None, reason)."""
        cands = [('private', p) for p in private]
        cands += self.std_dirs(bits)
        hidden = None
        for kind, d in cands:
            vp = f'{d}/{name}'
            r = self.vr.real(vp)
            if not r or not os.path.isfile(r):
                continue
            e = self.elf(r)
            if e.err or e.bits != bits:
                continue
            if kind in ('system', 'system_ext', 'product') and name not in self.allowed_sys:
                hidden = hidden or vp                  # in the tree, but a vendor process cannot load it
                continue
            return vp, r, kind
        sub = 'lib64' if bits == 64 else 'lib'
        for an, root in self.vr.apex.items():
            for d in (f'{root}/{sub}/bionic', f'{root}/{sub}'):
                f = os.path.join(d, name)
                if os.path.isfile(f):
                    e = self.elf(f)
                    if not e.err and e.bits == bits:
                        return f'/apex/{an}/{sub}/{name}', f, 'apex'
        if name in self.bionic or name in self.allowed_sys and (name in self.bionic or name.startswith('libc')):
            if not self.vr.apex:                       # APEX not unpacked: accept the bionic names
                return f'(name-only){name}', None, 'name-only'
        if hidden:
            return None, None, f'NOT-VISIBLE (only in {hidden}, not on the LLNDK/public list)'
        return None, None, 'not found'

    # ---- closure of one root --------------------------------------------------------------
    def closure(self, start_vpaths, private):
        """BFS from the start files. -> members {vpath: (real, kind)}, unresolved [(needer_vpath, soname, why)],
        dlopen edges [(from_vpath, target_vpath)]."""
        members, unresolved, dl_edges, dl_missing = collections.OrderedDict(), [], [], []
        queue = []
        for sv in start_vpaths:
            r = self.vr.real(sv)
            if not r or not os.path.isfile(r):
                unresolved.append(('(rc)', sv, 'start target missing'))
                continue
            queue.append((sv, r, 'root'))
        seen_real = set()
        while queue:
            vp, r, kind = queue.pop(0)
            rr = os.path.realpath(r)
            if rr in seen_real:
                continue
            seen_real.add(rr)
            e = self.elf(r)
            members[vp] = (r, kind)
            if e.err:
                unresolved.append((vp, '(self)', 'unreadable ELF: ' + e.err))
                continue
            if kind in PLATFORM_KINDS:
                continue           # a platform library resolves its own NEEDED in its own namespace
            for n in e.needed:
                tvp, tr, k = self.resolve(n, e.bits, private)
                if tr is None and k != 'name-only':
                    unresolved.append((vp, n, k))
                elif tr is not None:
                    queue.append((tvp, tr, k))
            for tgt in dlopen_targets(r, e):
                if tgt != vp:
                    tr2 = self.vr.real(tgt)
                    if tr2 and os.path.isfile(tr2):
                        dl_edges.append((vp, tgt))
                        queue.append((tgt, tr2, 'dlopen'))
                    else:
                        dl_missing.append((vp, tgt))
        return members, list(dict.fromkeys(unresolved)), dl_edges, dl_missing


PLATFORM_KINDS = ('system', 'system_ext', 'product', 'apex')
_DLOPEN_RE = re.compile(rb'/(?:odm|vendor|system|system_ext)/lib(?:64)?/[A-Za-z0-9_.+@-]+\.so')
_dlcache = {}


def dlopen_targets(real, e):
    """Full library paths inside the file's strings (a dlopen("/odm/lib64/x.so") that has no DT_NEEDED)."""
    rr = os.path.realpath(real)
    if rr not in _dlcache:
        try:
            with open(rr, 'rb') as f:
                data = f.read()
        except OSError:
            data = b''
        _dlcache[rr] = sorted({m.decode() for m in _DLOPEN_RE.findall(data)})
    return [t for t in _dlcache[rr] if (('/lib64/' in t) == (e.bits == 64))]


def demangle(names):
    if not names or not shutil.which('c++filt'):
        return {n: n for n in names}
    try:
        out = subprocess.run(['c++filt'], input='\n'.join(names), capture_output=True, text=True, timeout=60).stdout.split('\n')
        return {n: o for n, o in zip(names, out)}
    except (OSError, subprocess.SubprocessError):
        return {n: n for n in names}


# ---------------------------------------------------------------------------------------------- main

def odm_elfs(odm_root):
    res = []
    for dp, _dn, fn in os.walk(odm_root):
        for f in sorted(fn):
            p = os.path.join(dp, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            try:
                with open(p, 'rb') as fh:
                    if fh.read(4) != b'\x7fELF':
                        continue
            except OSError:
                continue
            res.append('/odm/' + os.path.relpath(p, odm_root).replace(os.sep, '/'))
    return sorted(res)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0], formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__)
    ap.add_argument('--tree', required=True, help='tree root with system system_ext product vendor odm')
    ap.add_argument('--odm', help='use this folder as /odm (for example an odm.img extracted with fsck.erofs)')
    ap.add_argument('--assume-no-private', action='store_true', help='ignore LD_LIBRARY_PATH of the rc files')
    ap.add_argument('--no-symbols', action='store_true', help='skip the undefined-symbol check')
    ap.add_argument('--abi-diff', metavar='OLD_ODM', help='also list export changes against this older odm folder')
    ap.add_argument('--strict', action='store_true', help='problems in ELF files that no service reaches also fail')
    ap.add_argument('--top', type=int, default=8, help='symbols listed for each ELF file (default 8)')
    ap.add_argument('--apex-cache', help='folder for the unpacked APEX payloads (default: a temporary folder)')
    ap.add_argument('-v', '--verbose', action='store_true', help='list every closure member')
    a = ap.parse_args()

    tree = os.path.abspath(a.tree)
    odm_dir = os.path.abspath(a.odm) if a.odm else os.path.join(tree, 'odm')
    for d in (tree, odm_dir):
        if not os.path.isdir(d):
            sys.exit(f'odm_closure: not a folder: {d}')
    vr = VRoot(tree, odm_dir, a.apex_cache)
    if not os.path.isdir(vr.system):
        sys.exit(f'odm_closure: no system folder in {tree}')
    vr.setup_apex()
    ck = Checker(vr, a.assume_no_private)
    print(f'tree      {tree}')
    print(f'odm       {odm_dir}')
    print(f'system    {vr.system}')
    print(f'apex      {", ".join(sorted(vr.apex)) or "none"}{"  (" + vr.apex_note + ")" if vr.apex_note else ""}')
    print(f'LLNDK/public names: {len(ck.allowed_sys)}')

    # roots: services that start from /odm or have an /odm library argument
    svcs = [s for s in collect_services(vr)
            if s.exe.startswith('/odm/') or any(x.startswith('/odm/') for x in s.dlopen_args)]
    all_elfs = odm_elfs(odm_dir)
    print(f'ELF files in /odm: {len(all_elfs)}')
    print(f'rc services that use /odm: {len(svcs)}')

    problems = 0
    warnings = 0
    reached = set()                    # real paths of every file in a service closure
    sym_jobs = []                      # (label, members, private)
    print('\n== services')
    for s in svcs:
        priv = [] if a.assume_no_private else s.ld_path
        starts = [s.exe] + s.dlopen_args
        members, unres, dl, dlm = ck.closure(starts, priv)
        for vp, (r, _k) in members.items():
            reached.add(os.path.realpath(r))
        missing_start = [u for u in unres if u[0] == '(rc)']
        real_unres = [u for u in unres if u[0] != '(rc)']
        state = 'ok'
        if real_unres:
            state = 'UNRESOLVED'
        elif missing_start:
            state = 'target missing'
        tag = ' (disabled)' if s.disabled else ''
        print(f'{s.name}{tag}: {" ".join(s.argv)}   [{s.rc}]'
              + (f'  LD_LIBRARY_PATH={":".join(priv)}' if priv else '') + f'\n    {len(members)} files in closure -> {state}')
        for needer, n, why in missing_start:
            print(f'    INFO  start target missing: {n}  (service is {"disabled" if s.disabled else "enabled"}; the file is not in the odm)')
        for needer, n, why in real_unres:
            print(f'    FAIL  {n}: {why}   (needed by {needer})')
            problems += 1
        for fr, to in dl:
            print(f'    dlopen string: {fr} -> {to}')
        for fr, to in dlm:
            print(f'    INFO  dlopen string names a file that is not in the tree: {to}   (in {os.path.basename(fr)}; not an error if the code checks the result)')
        if a.verbose:
            for vp, (r, k) in members.items():
                print(f'      {k:10s} {vp}')
        sym_jobs.append((s.name, members, priv))

    # ELF files in odm that no service reaches: closure without private dirs
    print('\n== other ELF files in /odm (not in the closure of an rc service)')
    orphans = []
    for vp in all_elfs:
        r = vr.real(vp)
        if os.path.realpath(r) in reached:
            continue
        orphans.append(vp)
        members, unres, _dl, _dlm = ck.closure([vp], [])
        sym_jobs.append((vp, members, []))
        if unres:
            for needer, n, why in unres:
                print(f'    {"FAIL" if a.strict else "WARN"}  {vp}: {n}: {why}   (needed by {needer})')
                if a.strict:
                    problems += 1
                else:
                    warnings += 1
    print(f'    {len(orphans)} files' + (':' if orphans else ''))
    for o in orphans:
        print(f'        {o}')

    # undefined symbols
    if not a.no_symbols:
        print('\n== undefined symbols (strong) of the /odm ELF files against the exports of the same closure')
        seen = set()
        nsym = 0
        nchecked = nfiles = 0
        for label, members, priv in sym_jobs:
            exports = set()
            for vp, (r, _k) in members.items():
                e = ck.elf(r)
                exports |= e.defs
            for vp, (r, _k) in members.items():
                if not vp.startswith('/odm/'):
                    continue
                key = (os.path.realpath(r), label if label in [s.name for s in svcs] else '')
                if key in seen:
                    continue
                seen.add(key)
                e = ck.elf(r)
                nfiles += 1
                nchecked += len(e.undef)
                miss = sorted({u for u in e.undef if u not in exports})
                if not miss:
                    continue
                fatal = label in [s.name for s in svcs] or a.strict
                shown = demangle(miss[:a.top])
                print(f'    {"FAIL" if fatal else "WARN"}  {vp}  [{label}]: {len(miss)} undefined symbols not exported by the closure')
                for m in miss[:a.top]:
                    print(f'        {shown[m]}')
                if len(miss) > a.top:
                    print(f'        ... {len(miss) - a.top} more')
                nsym += 1
                if fatal:
                    problems += 1
                else:
                    warnings += 1
        print(f'    checked {nchecked} strong undefined symbols in {nfiles} (file, service) pairs')
        if nsym == 0:
            print('    none: every undefined symbol has a definition in the closure')

    # export diff against an older odm (which exports a changed lib lost, and who still imports them)
    if a.abi_diff:
        print(f'\n== export changes against {a.abi_diff}')
        old_root = os.path.abspath(a.abi_diff)
        importers = collections.defaultdict(set)         # symbol -> files of the current odm that import it
        definers = collections.defaultdict(set)          # symbol -> files of the current odm that export it
        for vp in all_elfs:
            e = ck.elf(vr.real(vp))
            for u in e.undef:
                importers[u].add(vp)
            for dsym in e.defs:
                definers[dsym].add(vp)
        print('    (symbols of libc++ [std::__1] and symbols that another file in this odm still exports are not listed)')
        for vp in all_elfs:
            op = os.path.join(old_root, vp[len('/odm/'):])
            if not os.path.isfile(op):
                continue
            eo, en = Elf(op), ck.elf(vr.real(vp))
            if eo.err or en.err or eo.defs == en.defs:
                continue
            lost, gained = sorted(eo.defs - en.defs), sorted(en.defs - eo.defs)
            used = [x for x in lost if x in importers and not definers.get(x) and 'St3__1' not in x]
            print(f'    {vp}: -{len(lost)} +{len(gained)} exports; {len(used)} lost symbols are still imported by a file in this odm')
            for x in used[:a.top]:
                who = ', '.join(os.path.basename(y) for y in sorted(importers[x])[:3])
                print(f'        {demangle([x])[x]}   <- {who}')

    print('\n== summary')
    print(f'problems (fail): {problems}   warnings: {warnings}   ELF files: {len(all_elfs)}   service roots: {len(svcs)}')
    print('RESULT: ' + ('FAIL' if problems else 'OK'))
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
