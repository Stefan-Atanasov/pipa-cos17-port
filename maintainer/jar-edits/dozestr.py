import sys, zipfile
from loguru import logger; logger.remove()
from androguard.misc import AnalyzeDex
from androguard.core.dex import DEX
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if not n.endswith('.dex'): continue
    d = DEX(z.read(n))
    for c in d.get_classes():
        if 'DozeBrightnessStrategyExtImpl' in c.get_name():
            print('##', n, c.get_name())
            for m in c.get_methods():
                strs = set(); calls = set()
                for ins in m.get_instructions():
                    o = ins.get_output()
                    if ins.get_name().startswith('const-string'): strs.add(o.split(',',1)[1].strip())
                    if ins.get_name().startswith('invoke') and ('Brightness' in o or 'Doze' in o or 'getInteger' in o or 'getFloat' in o or 'SystemProperties' in o or 'Settings' in o): calls.add(o.split(',')[-1].strip())
                if strs or calls: print(' ', m.get_name(), '| strings:', sorted(strs)[:8], '| calls:', sorted(calls)[:8])
