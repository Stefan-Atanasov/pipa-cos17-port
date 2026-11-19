#!/usr/bin/env python3
# Build md5 index (path -> md5/size/link) for all candidate trees. Output: idx/<name>.tsv
import os,sys,hashlib,concurrent.futures as cf
R='/mnt/reference/pipa/reference'; import os; P=os.environ.get('PIPA_ROOT', os.path.expanduser('~/Documents/pipa'))
W=P+'/port-work/fromstock/vendor'
trees={
 'b4v':W+'/x/b4v','b4o':W+'/x/b4o','c06v':W+'/x/c06v','c06o':W+'/x/c06o',
 'px_v':R+'/pixelos/vendor','px_o':R+'/pixelos/odm',
 'hy_v':R+'/hyperos1-stock/vendor','hy_o':R+'/hyperos1-stock/odm',
 'iq31_v':R+'/iqraos3.1/vendor','iq31_o':R+'/iqraos3.1/odm',
 'iq10_v':R+'/iqraos_v1.0/vendor','iq10_o':R+'/iqraos_v1.0/odm',
 'core':P+'/COS17/pipa_core','port':P+'/COS17/port-rom',
}
def md5(p):
    h=hashlib.md5()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()
os.makedirs(W+'/idx',exist_ok=True)
for n,t in trees.items():
    if not os.path.isdir(t): print('missing',n); continue
    ents=[]
    for d,_,fs in os.walk(t):
        for f in fs:
            p=os.path.join(d,f); ents.append(p)
    def one(p):
        rel=os.path.relpath(p,t)
        if os.path.islink(p): return (rel,'LINK',0,os.readlink(p))
        return (rel,md5(p),os.path.getsize(p),'')
    with cf.ThreadPoolExecutor(8) as ex: res=sorted(ex.map(one,ents))
    with open(W+'/idx/%s.tsv'%n,'w') as o:
        for r in res: o.write('\t'.join(map(str,r))+'\n')
    print(n,len(res),flush=True)
