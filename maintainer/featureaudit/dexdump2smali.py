#!/usr/bin/env python3
"""Turn `dexdump -d` output into smali-like text (only .class, .method and instructions) for callsites.py.
Use for dex files that baksmali 2.5.2 cannot read (Android 16+ hidden-API flags in boot jars).
Usage: dexdump -d classes.dex | python3 -I dexdump2smali.py > out.smali"""
import re, sys
cls = None
in_methods = False
sys.stdin.reconfigure(encoding="utf-8", errors="replace")
for line in sys.stdin:
    m = re.match(r"\s*Class descriptor\s*:\s*'(L[^']+;)'", line)
    if m:
        print(f'.class public {m.group(1)}'); in_methods = False; continue
    if re.match(r'\s*(Direct|Virtual) methods\s*-', line):
        in_methods = True; continue
    if re.match(r'\s*(Static|Instance) fields\s*-', line):
        in_methods = False; continue
    if in_methods:
        m = re.match(r"\s*name\s*:\s*'([^']+)'", line)
        if m:
            print('.end method'); print(f'.method public {m.group(1)}'); continue
    m = re.match(r'^[0-9a-f]+:[ 0-9a-f]+\|[0-9a-f]+: (.*)$', line.rstrip('\n'))
    if m:
        ins = re.sub(r'\s+// .*$', '', m.group(1))
        ins = re.sub(r'#int (-?\d+)', r'\1', ins)
        ins = re.sub(r'#long (-?\d+)', r'\1', ins)
        print('    ' + ins)
