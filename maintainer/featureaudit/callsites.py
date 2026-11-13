#!/usr/bin/env python3
"""Feature audit: find the smali call sites of property / feature names.

Usage: python3 -I callsites.py <smali root> <names.txt> <out.tsv>
  <smali root>: one folder per apk/jar (baksmali output), e.g. port-work/feature-audit-smali
  <names.txt>:  one name per line
Output columns: name, container, class, method, api, default, line
  api     = the first invoke within 12 lines after `const-string vX, "<name>"` that takes the string register
  default = the literal (const/4, const/16, const-string) loaded into the next argument register, if any
"""
import os, re, sys, subprocess, collections

ROOT, NAMES, OUT = sys.argv[1:4]
names = [l.strip() for l in open(NAMES) if l.strip()]
nameset = set(names)

# 1. rg finds the candidate lines fast
pat_file = OUT + '.pat'
with open(pat_file, 'w') as f:
    for n in names:
        f.write(f'"{n}"\n')
rg = subprocess.run(['rg', '-F', '-l', '-f', pat_file, '--glob', '*.smali', ROOT],
                    capture_output=True, text=True)
files = rg.stdout.split()
os.unlink(pat_file)

CONST = re.compile(r'^\s*const-string(?:/jumbo)?\s+([vp]\d+),\s*"((?:[^"\\]|\\.)*)"')
INVOKE = re.compile(r'^\s*invoke-\w+(?:/range)?\s+\{([^}]*)\},\s*(\S+)')
LIT = re.compile(r'^\s*const(?:/4|/16|/high16)?\s+([vp]\d+),\s*(-?0x[0-9a-f]+|-?\d+)')
LITS = re.compile(r'^\s*const-string(?:/jumbo)?\s+([vp]\d+),\s*"((?:[^"\\]|\\.)*)"')
METHOD = re.compile(r'^\.method\s+.*?(\S+)$')
CLASS = re.compile(r'^\.class\s+.*?(L\S+;)$')

def regs(s):
    s = s.strip()
    if '..' in s:  # range
        a, b = [x.strip() for x in s.split('..')]
        if a[0] == b[0]:
            return [f'{a[0]}{i}' for i in range(int(a[1:]), int(b[1:]) + 1)]
        return [a, b]
    return [x.strip() for x in s.split(',') if x.strip()]

rows = []
for path in files:
    rel = os.path.relpath(path, ROOT)
    container = rel.split(os.sep)[0]
    try:
        lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        continue
    cls, meth = '?', '?'
    for i, line in enumerate(lines):
        m = CLASS.match(line)
        if m:
            cls = m.group(1)
            continue
        m = METHOD.match(line)
        if m:
            meth = m.group(1)
            continue
        m = CONST.match(line)
        if not m or m.group(2) not in nameset:
            continue
        reg, name = m.group(1), m.group(2)
        api, default = '', ''
        lits = {}
        for j in range(i + 1, min(i + 13, len(lines))):
            l2 = lines[j]
            ml = LIT.match(l2)
            if ml:
                lits[ml.group(1)] = ml.group(2)
            ms = LITS.match(l2)
            if ms:
                lits[ms.group(1)] = '"' + ms.group(2)[:40] + '"'
            mi = INVOKE.match(l2)
            if mi:
                rs = regs(mi.group(1))
                if reg in rs:
                    api = mi.group(2)
                    k = rs.index(reg)
                    if k + 1 < len(rs):
                        default = lits.get(rs[k + 1], '')
                    break
            if l2.strip().startswith(('.end method', 'return')):
                break
        api = re.sub(r'^L([^;]+);->', lambda m: m.group(1).split('/')[-1] + '.', api)
        rows.append((name, container, cls, meth, api, default, str(i + 1)))

rows.sort()
with open(OUT, 'w') as f:
    f.write('name\tcontainer\tclass\tmethod\tapi\tdefault\tline\n')
    for r in rows:
        f.write('\t'.join(r) + '\n')
found = collections.Counter(r[0] for r in rows)
print(f'names: {len(names)}  with call sites: {len(found)}  sites: {len(rows)}  files scanned: {len(files)}')
