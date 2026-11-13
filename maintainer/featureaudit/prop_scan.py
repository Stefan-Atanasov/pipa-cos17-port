#!/usr/bin/env python3
"""Feature audit, offline part (a): which properties and OPPO features does the ROM code read that the ROM never sets?

Usage: python3 -I prop_scan.py <tree> <outdir>
  <tree> = folder with system/ system_ext/ product/ vendor/ odm/ (fsck.erofs --extract of a pt build).

Output (in <outdir>):
  set_props.tsv       name, value, source file (build.prop/*.prop, static `setprop` in init .rc)
  read_props.tsv      name, number of reader files, reader files (dex strings of apk/jar, strings of ELF)
  missing_props.tsv   read but never set; sorted by prefix group
  features_declared.tsv / features_read.tsv / missing_features.tsv  (oplus.* / com.oplus.* feature names)
The scan is string based: a string in a dex or ELF is a "read" candidate, not a proven SystemProperties call.
Triage (what each missing name gates) is a separate, manual step.
"""
import os, re, sys, struct, zipfile, io, collections

TREE, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

PROP_RE = re.compile(rb'(?<![A-Za-z0-9_.\-])((?:ro|persist|sys|vendor|debug|oplus|odm|dalvik|init\.svc|ctl|service|'
                     rb'bluetooth|wifi|telephony|gsm|net|media|audio|camera|graphics|hw|log|security|'
                     rb'oem|opluscust|cust|qemu|config|dev|drm|nfc|ril|vold|wlan|surfaceflinger|'
                     rb'apexd|apex|bootreceiver|setupwizard|aaudio|af|tunnel|pm|ota|ext4|selinux|'
                     rb'logd|lmkd|heapprofd|traced|cache_key|ab|rescueparty|binder|framework)'
                     rb'\.[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)*)(?![A-Za-z0-9_.\-])')
FEAT_RE = re.compile(rb'(?<![A-Za-z0-9_.\-])((?:oplus|oppo|com\.oplus|com\.oppo|os\.oplus|android\.hardware)\.'
                     rb'(?:software|hardware|feature|aod|camera|display|audio|bt|wlan|gamespace|'
                     rb'launcher|systemui|settings|location|charge|power|screen|game)[A-Za-z0-9_.\-]*)(?![A-Za-z0-9_.\-])')
# strings that look like props but are java packages / file names
NOT_PROP = re.compile(r'\.(java|xml|so|apk|jar|png|json|db|txt|conf|cfg|rc|prop|dex|kt|html|bin|img|zip|rs|c|cc|cpp|h|'
                      r'py|sh|log|ini|dat|webp|jpg|ttf|otf|mp3|ogg|wav|proto|aidl|hal|smali|class|odex|vdex|art)$|'
                      r'^(android|com|org|java|javax|kotlin|dalvik\.system|dalvik\.annotation)\.')

def dex_strings(buf):
    """All strings of a dex file (MUTF-8, decoded leniently)."""
    if buf[:4] != b'dex\n' or len(buf) < 0x70:
        return []
    n, off = struct.unpack_from('<II', buf, 0x38)
    out = []
    for i in range(n):
        (so,) = struct.unpack_from('<I', buf, off + 4 * i)
        # skip uleb128 length
        p = so
        while buf[p] & 0x80:
            p += 1
        p += 1
        e = buf.index(b'\0', p)
        out.append(buf[p:e])
    return out

def elf_strings(path, minlen=6):
    try:
        with open(path, 'rb') as f:
            data = f.read()
    except OSError:
        return []
    return re.findall(rb'[\x20-\x7e]{%d,}' % minlen, data)

def iter_code(tree):
    """Yield (relpath, list_of_strings) for each dex container and ELF."""
    for root, dirs, files in os.walk(tree):
        if '/oat' in root or root.endswith('/oat'):
            continue
        for fn in files:
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, tree)
            if os.path.islink(path):
                continue
            low = fn.lower()
            try:
                if low.endswith(('.apk', '.jar', '.apex', '.capex')) or low.endswith('.opex'):
                    yield rel, list(zip_dex_strings(path))
                elif low.endswith('.dex'):
                    with open(path, 'rb') as f:
                        yield rel, dex_strings(f.read())
                else:
                    with open(path, 'rb') as f:
                        head = f.read(4)
                    if head == b'\x7fELF':
                        yield rel, elf_strings(path)
            except Exception as e:  # noqa: BLE001 (best effort scan)
                print('skip', rel, e, file=sys.stderr)

def zip_dex_strings(path, depth=0):
    try:
        z = zipfile.ZipFile(path)
    except Exception:
        return
    with z:
        for info in z.infolist():
            n = info.filename
            if n.endswith('.dex'):
                for s in dex_strings(z.read(info)):
                    yield s
            elif depth < 2 and n.endswith(('.apk', '.jar', '.zip')):  # nested (apex payloads are images: skipped)
                data = z.read(info)
                tmp = io.BytesIO(data)
                try:
                    with zipfile.ZipFile(tmp) as z2:
                        for i2 in z2.infolist():
                            if i2.filename.endswith('.dex'):
                                for s in dex_strings(z2.read(i2)):
                                    yield s
                except Exception:
                    pass

# ---------- 1. properties that the ROM sets ----------
set_props = {}
def add_set(name, val, src):
    set_props.setdefault(name, (val, src))

for root, dirs, files in os.walk(TREE):
    for fn in files:
        path = os.path.join(root, fn)
        if os.path.islink(path):
            continue
        rel = os.path.relpath(path, TREE)
        if rel.endswith('pipa_port/config.prop'):
            continue  # pipa_port's own KEY=value config, not Android properties
        if fn.endswith('.prop') or fn == 'prop.default':
            try:
                for line in open(path, encoding='utf-8', errors='replace'):
                    line = line.strip()
                    if not line or line.startswith('#') or '=' not in line:
                        continue
                    if line.startswith('import '):
                        continue
                    k, v = line.split('=', 1)
                    add_set(k.strip(), v.strip(), rel)
            except OSError:
                pass
        elif fn.endswith('.rc') or fn.endswith('.sh'):
            try:
                txt = open(path, encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            for m in re.finditer(r'(?:^|\s)setprop\s+([A-Za-z0-9_.\-]+)\s+(\S*)', txt):
                add_set(m.group(1), m.group(2), rel)
            for m in re.finditer(r'resetprop\s+(?:-n\s+)?([A-Za-z0-9_.\-]+)\s+(\S*)', txt):
                add_set(m.group(1), m.group(2), rel)

with open(os.path.join(OUT, 'set_props.tsv'), 'w') as f:
    for k in sorted(set_props):
        v, s = set_props[k]
        f.write(f'{k}\t{v}\t{s}\n')

# ---------- 2. declared OPPO features ----------
feat_decl = {}
for root, dirs, files in os.walk(TREE):
    for fn in files:
        if not fn.endswith('.xml'):
            continue
        path = os.path.join(root, fn)
        if os.path.islink(path):
            continue
        try:
            txt = open(path, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        if 'feature' not in txt:
            continue
        rel = os.path.relpath(path, TREE)
        for m in re.finditer(r'<(?:oplus-feature|feature|unavailable-feature|app_feature|feature_item)\b[^>]*\bname\s*=\s*"([^"]+)"', txt):
            feat_decl.setdefault(m.group(1), rel)
        for m in re.finditer(r'<(?:oplus-feature|feature)\b[^>]*>\s*([a-z][A-Za-z0-9_.\-]+)\s*<', txt):
            feat_decl.setdefault(m.group(1), rel)
with open(os.path.join(OUT, 'features_declared.tsv'), 'w') as f:
    for k in sorted(feat_decl):
        f.write(f'{k}\t{feat_decl[k]}\n')

# ---------- 3. names the code reads ----------
readers = collections.defaultdict(set)
freaders = collections.defaultdict(set)
for rel, strs in iter_code(TREE):
    seen_p, seen_f = set(), set()
    for s in strs:
        if len(s) > 200:
            # long strings (shell scripts, help text) can still hold prop names
            pass
        for m in PROP_RE.finditer(s):
            seen_p.add(m.group(1))
        for m in FEAT_RE.finditer(s):
            seen_f.add(m.group(1))
    for p in seen_p:
        try:
            n = p.decode()
        except UnicodeDecodeError:
            continue
        if NOT_PROP.search(n) or n.endswith('.') or len(n) < 5:
            continue
        readers[n].add(rel)
    for p in seen_f:
        try:
            freaders[p.decode()].add(rel)
        except UnicodeDecodeError:
            pass

def group(name):
    parts = name.split('.')
    return '.'.join(parts[:2]) if len(parts) > 2 else parts[0]

def write_read(path, d):
    with open(path, 'w') as f:
        for k in sorted(d):
            r = sorted(d[k])
            f.write(f'{k}\t{len(r)}\t{" ".join(r[:25])}\n')

write_read(os.path.join(OUT, 'read_props.tsv'), readers)
write_read(os.path.join(OUT, 'features_read.tsv'), freaders)

missing = {k: v for k, v in readers.items() if k not in set_props}
with open(os.path.join(OUT, 'missing_props.tsv'), 'w') as f:
    for k in sorted(missing, key=lambda x: (group(x), x)):
        r = sorted(missing[k])
        f.write(f'{group(k)}\t{k}\t{len(r)}\t{" ".join(r[:25])}\n')
mf = {k: v for k, v in freaders.items() if k not in feat_decl}
with open(os.path.join(OUT, 'missing_features.tsv'), 'w') as f:
    for k in sorted(mf):
        r = sorted(mf[k])
        f.write(f'{k}\t{len(r)}\t{" ".join(r[:25])}\n')

cnt = collections.Counter(group(k) for k in missing)
print(f'set props: {len(set_props)}  read names: {len(readers)}  missing: {len(missing)}')
print(f'declared features: {len(feat_decl)}  read feature names: {len(freaders)}  missing: {len(mf)}')
for g, c in cnt.most_common(40):
    print(f'  {c:5d}  {g}')
