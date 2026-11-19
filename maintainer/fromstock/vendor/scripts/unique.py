#!/usr/bin/env python3
# usage: unique.py v|o : classify UNIQUE rows -> unique-<k>.tsv, text diffs into patches/
import sys,os,subprocess,difflib
import os; W=os.environ.get('W', os.path.expanduser('~/Documents/pipa/port-work/fromstock/vendor'))
k=sys.argv[1]; R='/mnt/reference/pipa/reference'
b4=W+'/x/b4'+k
pxt=R+'/pixelos/'+('vendor' if k=='v' else 'odm')
alt={'hy':R+'/hyperos1-stock/'+('vendor' if k=='v' else 'odm'),'c06':W+'/x/c06'+k,
     'iq31':R+'/iqraos3.1/'+('vendor' if k=='v' else 'odm')}
if k=='o': alt['c06v']=W+'/x/c06v'
core=os.path.expanduser('~/Documents/pipa/COS17/pipa_core')
def istext(p):
    try:
        d=open(p,'rb').read(65536)
    except: return False
    if b'\0' in d: return False
    try: d.decode('utf-8')
    except: return False
    return True
def ndiff(a,b):
    A=open(a,'rb').read(); B=open(b,'rb').read()
    if len(A)!=len(B): return 'size %d vs %d'%(len(B),len(A))
    n=sum(1 for x,y in zip(A,B) if x!=y)
    return '%d bytes differ'%n
rows=[l.rstrip('\n').split('\t') for l in open(W+('/vendor-delta.tsv' if k=='v' else '/odm-delta.tsv'))][1:]
out=open(W+'/unique-%s.tsv'%k,'w'); out.write('path\tstatus\tsize\tkind\tcounterpart\tdetail\n')
for p,st,s,src,note in rows:
    if src!='UNIQUE': continue
    f=os.path.join(b4,p)
    if os.path.islink(f): out.write('\t'.join([p,st,'0','link','-','; '.join([note])])+'\n'); continue
    kind='text' if istext(f) else 'binary'
    cp=None; det=''
    px=os.path.join(pxt,p)
    if os.path.isfile(px) and not os.path.islink(px): cp='px'; ref=px
    else:
        ref=None
        for n,d in alt.items():
            q=os.path.join(d,p)
            if os.path.isfile(q): cp=n+'(other base)'; ref=q; break
        if ref is None:
            bn=os.path.basename(p)
            if os.path.isfile(core+'/facehal/lib64/'+bn): ref=core+'/facehal/lib64/'+bn; cp='pipa_core/facehal'
            elif p.endswith('facehal') : ref=core+'/facehal/'+bn; cp='pipa_core/facehal'
    if ref:
        if kind=='text':
            od=W+'/patches/'+('vendor' if k=='v' else 'odm')+'/'+p.replace('/','__')+'.diff'
            r=subprocess.run(['diff','-u','--label','a/'+p,'--label','b/'+p,ref,f],capture_output=True)
            open(od,'wb').write(r.stdout)
            d=r.stdout.decode('utf-8','replace').splitlines()
            det='diff +%d -%d (raw bytes, apply: patch --binary)'%(sum(1 for x in d if x.startswith('+') and not x.startswith('+++')),sum(1 for x in d if x.startswith('-') and not x.startswith('---')))
        else: det=ndiff(ref,f)
    elif kind=='text':
        # new text file: store full copy as patch (against /dev/null)
        od=W+'/patches/'+('vendor' if k=='v' else 'odm')+'/'+p.replace('/','__')+'.new'
        open(od,'wb').write(open(f,'rb').read()); det='new file -> patches/*.new'
    out.write('\t'.join([p,st,s,kind,cp or '-',det])+'\n')
