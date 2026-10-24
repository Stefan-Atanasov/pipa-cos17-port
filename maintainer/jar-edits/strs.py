import sys,glob
from androguard.core.dex import DEX
def strs(d):
    s=set()
    for f in sorted(glob.glob(d+'/classes*.dex')):
        s|=set(str(x) for x in DEX(open(f,'rb').read()).get_strings())
    return s
a=strs('b4');b=strs('c06')
open('only_b4.txt','w').write('\n'.join(sorted(a-b)))
open('only_c06.txt','w').write('\n'.join(sorted(b-a)))
print(len(a),len(b),len(a-b),len(b-a))
