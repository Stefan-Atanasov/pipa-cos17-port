#!/usr/bin/env python3
"""Feature audit: rank the output of prop_scan.py for triage.

Usage: python3 -I prioritize.py <scan dir> [<oppo-ref dir with ref_props.tsv / ref_features.tsv>]
Writes <scan dir>/triage/: P1.tsv P2.tsv P3.tsv features.tsv, and per-component lists (by_<comp>.tsv).
Columns: prio, name, ref (value on a real OPPO device, if known), comp, nreaders, readers
"""
import os, re, sys, collections

SCAN = sys.argv[1]
REF = sys.argv[2] if len(sys.argv) > 2 else None
OUT = os.path.join(SCAN, 'triage')
os.makedirs(OUT, exist_ok=True)

def load_ref(fn, ncols):
    d = {}
    if not REF or not os.path.exists(os.path.join(REF, fn)):
        return d
    for line in open(os.path.join(REF, fn), encoding='utf-8', errors='replace'):
        f = line.rstrip('\n').split('\t')
        if len(f) < ncols or not f[0] or f[0].startswith('#'):
            continue
        d.setdefault(f[0], []).append('|'.join(f[1:ncols]))
    return d

ref_props = load_ref('ref_props.tsv', 3)      # name -> ["value|device", ...]
ref_feats = load_ref('ref_features.tsv', 2)   # name -> ["device", ...]

DROP = re.compile(r'\.(intent|action|permission|provider|receiver|category|extra|key|notification|broadcast)\.|'
                  r'^(sys|init\.svc|ro\.boot|ctl|dev|net|debug|log\.tag|media\.mojom|drm\.mediadrm|service\.bootanim)\.|'
                  r'[A-Z]|[_.\-]$|\.\.')
OPLUS = re.compile(r'oplus|oppo|coloros|^ro\.odm\.|^ro\.separate|^ro\.rom\.|^ro\.config\.|heytap|^ro\.product\.oplus')

def comp(readers):
    c = set()
    for r in readers:
        low = r.lower()
        if r.endswith(('.apk',)):
            if 'systemui' in low:
                c.add('sysui')
            elif 'settings' in low:
                c.add('settings')
            elif 'launcher' in low:
                c.add('launcher')
            else:
                c.add('apps')
        elif r.endswith(('.jar', '.apex', '.capex', '.opex')):
            c.add('framework')
        else:
            c.add('native')
    return c

rows = []
for line in open(os.path.join(SCAN, 'missing_props.tsv'), encoding='utf-8'):
    g, name, n, readers = (line.rstrip('\n').split('\t') + [''])[:4]
    readers = readers.split()
    if DROP.search(name):
        continue
    cs = comp(readers)
    java = bool(cs - {'native'})
    ref = ';'.join(ref_props.get(name, [])[:3])
    if name.startswith(('oplus.software.', 'oplus.hardware.')):
        continue  # features, handled below
    if name.startswith('ro.') and OPLUS.search(name) and java:
        p = 'P1'
    elif name.startswith('ro.') and java:
        p = 'P2'
    elif name.startswith('persist.') and OPLUS.search(name) and java:
        p = 'P2'
    elif OPLUS.search(name) and java:
        p = 'P3'
    elif name.startswith('ro.') and OPLUS.search(name):
        p = 'P3'   # native only
    else:
        continue
    if ref and p != 'P1':
        p = 'P1'   # a real OPPO device sets it: always worth a look
    rows.append((p, name, ref, ','.join(sorted(cs)), len(readers), ' '.join(readers[:12])))

feat = []
for line in open(os.path.join(SCAN, 'missing_features.tsv'), encoding='utf-8'):
    name, n, readers = (line.rstrip('\n').split('\t') + [''])[:3]
    readers = readers.split()
    if not re.match(r'^(oplus|oppo|com\.oplus|com\.oppo)\.(software|hardware)\.[a-z0-9_.]+$', name) or name.endswith('.'):
        continue
    ref = ';'.join(ref_feats.get(name, [])[:3])
    cs = comp(readers)
    feat.append(('F1' if ref else 'F2', name, ref, ','.join(sorted(cs)), len(readers), ' '.join(readers[:12])))

def dump(fn, rs):
    with open(os.path.join(OUT, fn), 'w') as f:
        f.write('prio\tname\tref\tcomp\tnreaders\treaders\n')
        for r in rs:
            f.write('\t'.join(map(str, r)) + '\n')

rows.sort(key=lambda r: (r[0], r[1]))
feat.sort(key=lambda r: (r[0], r[1]))
for p in ('P1', 'P2', 'P3'):
    dump(f'{p}.tsv', [r for r in rows if r[0] == p])
dump('features.tsv', feat)
by = collections.defaultdict(list)
for r in rows + feat:
    if r[0] in ('P3', 'F2') and not r[2]:
        continue
    # one owner per name: the first UI component wins, then framework, then native
    cs = r[3].split(',')
    for c in ('sysui', 'settings', 'launcher', 'apps', 'framework', 'native'):
        if c in cs:
            by[c].append(r)
            break
for c, rs in by.items():
    dump(f'by_{c}.tsv', rs)
cnt = collections.Counter(r[0] for r in rows + feat)
print('counts:', dict(sorted(cnt.items())))
print('per component (P1/P2/F1 + referenced):', {c: len(v) for c, v in sorted(by.items())})
print('ref props loaded:', len(ref_props), ' ref features loaded:', len(ref_feats))
