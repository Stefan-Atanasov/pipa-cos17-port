#!/usr/bin/env python3
# usage: delta.py v|o  -> vendor-delta.tsv / odm-delta.tsv
import sys,os,collections
import os; W=os.environ.get('W', os.path.expanduser('~/Documents/pipa/port-work/fromstock/vendor'))
k=sys.argv[1]
def load(n):
    d={}
    for l in open(W+'/idx/%s.tsv'%n):
        p,m,s,t=l.rstrip('\n').split('\t'); d[p]=(m,int(s),t)
    return d
b4=load('b4'+k); base=load('px_'+k)
# source pool, priority order
order=['px_v','hy_v','iq31_v','iq10_v','c06v','px_o','hy_o','iq31_o','iq10_o','c06o','core','port']
pool=collections.defaultdict(list)
for n in order:
    try: d=load(n)
    except Exception: continue
    for p,(m,s,t) in d.items():
        if m!='LINK': pool[m].append((n,p))
rows=[]
for p,(m,s,t) in sorted(b4.items()):
    if p in base:
        bm,bs,bt=base[p]
        if (m,t)==(bm,bt): rows.append((p,'same',s,'px_'+k+':'+p,'')); continue
        st='modified'
    else: st='added'
    if m=='LINK':
        rows.append((p,st,0,'UNIQUE','symlink -> '+t+(' (px: %s)'%base[p][2] if p in base else ''))); continue
    src=pool.get(m,[])
    if src: rows.append((p,st,s,src[0][0]+':'+src[0][1],'also %d more'%(len(src)-1) if len(src)>1 else ''))
    else: rows.append((p,st,s,'UNIQUE','px size %d'%base[p][1] if p in base else 'no px counterpart'))
for p,(m,s,t) in sorted(base.items()):
    if p not in b4: rows.append((p,'removed',s,'-',''))
out=W+('/vendor-delta.tsv' if k=='v' else '/odm-delta.tsv')
with open(out,'w') as o:
    o.write('path\tstatus\tsize\tsource\tnote\n')
    for r in rows: o.write('\t'.join(map(str,r))+'\n')
c=collections.Counter((r[1],'UNIQUE' if r[3]=='UNIQUE' else ('-' if r[1] in('same','removed') else r[3].split(':')[0])) for r in rows)
for kk,v in sorted(c.items()): print(kk,v)
