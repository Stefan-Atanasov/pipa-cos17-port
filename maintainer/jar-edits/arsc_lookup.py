import sys, zipfile
from loguru import logger; logger.remove()
from androguard.core.axml import ARSCParser
apk, names = sys.argv[1], sys.argv[2:]
a = ARSCParser(zipfile.ZipFile(apk).read('resources.arsc'))
pkg = a.get_packages_names()[0]
for n in names:
    hit = False
    for t in ('integer', 'dimen', 'bool', 'array', 'fraction', 'string'):
        rid = a.get_res_id_by_key(pkg, t, n)
        if rid:
            hit = True
            vals = a.get_resolved_res_configs(rid)
            print(f"{t}/{n} 0x{rid:08x}: " + "; ".join(f"[{c.get_qualifier() or 'default'}] {v}" for c, v in vals[:4]))
    if not hit: print(f"{n}: not defined")
