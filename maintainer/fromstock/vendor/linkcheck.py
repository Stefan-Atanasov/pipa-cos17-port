#!/usr/bin/env python3
# linkcheck.py NEW_TREE OLD_TREE: after a swap of vendor files, list symbols that a vendor library gave in OLD but no
# vendor library gives in NEW (LOST), and new undefined symbols that the system must give. Trees from
# `fsck.erofs --extract=<dir> --no-preserve vendor.img`. Needs llvm-readelf and llvm-nm. fs1a: 100788 uses, 0 lost.
# Regression check between two vendor trees with the same paths: for each ELF and each undefined dynamic symbol,
# was it defined by a vendor lib in its NEEDED closure in OLD, and is it still defined by one in NEW?
import os, subprocess, sys
def elfs(root):
    for d,_,fs in os.walk(root):
        for f in fs:
            p=os.path.join(d,f)
            if os.path.islink(p): continue
            try:
                with open(p,'rb') as h:
                    if h.read(4)==b'\x7fELF': yield p
            except OSError: pass
def load(root):
    E={}; byname={}
    for p in elfs(root):
        r=subprocess.run(['llvm-readelf','-d','-h',p],capture_output=True,text=True).stdout
        need=[l.split('[')[1].split(']')[0] for l in r.splitlines() if 'Shared library:' in l]
        cls='64' if 'ELF64' in r else '32'
        d=set(subprocess.run(['llvm-nm','-D','--defined-only','-j',p],capture_output=True,text=True).stdout.split())
        u=set(subprocess.run(['llvm-nm','-D','--undefined-only','-j',p],capture_output=True,text=True).stdout.split())
        rel=os.path.relpath(p,root); E[rel]=(need,cls,d,u)
        byname.setdefault((os.path.basename(p),cls),rel)
    return E,byname
def vprov(E,byname,rel):
    need,cls,_,_=E[rel]; seen=set(); stack=list(need); prov=set()
    while stack:
        n=stack.pop()
        if n in seen: continue
        seen.add(n); c=byname.get((n,cls))
        if c is None: continue
        prov|=E[c][2]; stack+=E[c][0]
    return prov
O,ob=load(sys.argv[2]); N,nb=load(sys.argv[1])
reg=[]; used=0
for rel,(need,cls,d,u) in N.items():
    if rel not in O: continue
    po=vprov(O,ob,rel); pn=vprov(N,nb,rel)
    ou=O[rel][3]
    for s in ou & po:          # symbols the old file took from vendor libs
        used+=1
        if s in u and s not in pn and s not in d: reg.append((rel,s))
    for s in u - ou:           # new undefined symbols of a swapped file: must come from vendor or system
        if s not in pn and s not in d: reg.append((rel,'NEW-UNDEF?'+s))
print('elfs',len(N),'vendor-resolved symbol uses',used)
hard=[r for r in reg if not r[1].startswith('NEW-UNDEF?')]; soft=[r for r in reg if r[1].startswith('NEW-UNDEF?')]
print('LOST (vendor symbol no longer provided):',len(hard))
for r in hard[:40]: print('  ',*r)
print('new undefined symbols not in vendor (system must provide):',len(soft))
from collections import Counter
print(Counter(r[0] for r in soft).most_common(15))
