#!/usr/bin/env python3
"""BUGS-TODO 12: make the pipa_port domain enforcing in system_ext_sepolicy.cil (and _debug.cil).

Removes "(typepermissive pipa_port)" and adds pipa_port_rules.cil after "(type pipa_port)". Writes in place (same
inode, label kept). Stops if the file does not look as expected (exactly one of each anchor).
usage: pipa_port_enforce.py <system_ext_sepolicy.cil>
"""
import os
import sys

p = sys.argv[1]
rules = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "pipa_port_rules.cil")).read()
s = open(p, encoding="utf-8", errors="surrogateescape").read()
for a in ("(type pipa_port)\n", "(typepermissive pipa_port)\n"):
    if s.count(a) != 1:
        sys.exit(f"{p}: '{a.strip()}' found {s.count(a)} times, expected 1")
s = s.replace("(typepermissive pipa_port)\n", "").replace("(type pipa_port)\n", "(type pipa_port)\n" + rules)
with open(p, "r+", encoding="utf-8", errors="surrogateescape") as f:
    f.write(s)
    f.truncate()
print(f"{p}: pipa_port enforcing, {rules.count('(allow ')} allow rules")
