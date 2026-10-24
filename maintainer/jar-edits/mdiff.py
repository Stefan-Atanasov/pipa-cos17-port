import glob,sys,pickle,logging
from loguru import logger
logger.remove()
from androguard.core.dex import DEX
def load(d):
    m={}
    for f in sorted(glob.glob(d+'/classes*.dex')):
        dx=DEX(open(f,'rb').read())
        for c in dx.get_classes():
            cn=c.get_name()
            for me in c.get_methods():
                code=me.get_code()
                if code is None: txt=None
                else:
                    txt='\n'.join(i.get_name()+' '+i.get_output() for i in code.get_bc().get_instructions())
                m[(cn,me.get_name(),str(me.get_descriptor()))]=txt
    return m
a=load('b4');b=load('c06')
pickle.dump((a,b),open('methods.pkl','wb'))
print(len(a),len(b))
