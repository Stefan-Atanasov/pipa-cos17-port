import sys, zipfile
from loguru import logger; logger.remove()
from androguard.core.dex import DEX
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if not n.endswith('.dex'): continue
    d = DEX(z.read(n))
    for c in d.get_classes():
        if c.get_name().endswith('DozeBrightnessStrategyExtImpl;'):
            for m in c.get_methods():
                print('##', m.get_name(), m.get_descriptor())
                for ins in m.get_instructions():
                    print('   ', ins.get_name(), ins.get_output()[:140])
