import pickle,re
a,b=pickle.load(open('methods.pkl','rb'))
def norm(t):
    if t is None:return None
    return re.sub(r'(v|p)\d+','R',t) if False else t
oa=sorted(set(a)-set(b));ob=sorted(set(b)-set(a))
print('only b4',len(oa));print('only c06',len(ob))
ch=[k for k in a if k in b and a[k]!=b[k]]
print('changed',len(ch))
open('changed.txt','w').write('\n'.join(map(str,ch)))
open('onlyb4.txt','w').write('\n'.join(map(str,oa)))
open('onlyc06.txt','w').write('\n'.join(map(str,ob)))
