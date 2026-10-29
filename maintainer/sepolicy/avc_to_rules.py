#!/usr/bin/env python3
"""Turn pipa_port AVC denials into CIL allow rules (BUGS-TODO 12).

Input: logcat/dmesg text with "avc: denied" lines (from a permissive boot with persist.logd.audit.rate=2000, so no
denial is rate-limited away). Output (stdout): CIL. Reads of /proc/<pid> of any process (pgrep, pidof, ps) collapse to
the `domain` attribute; all other accesses stay per type.
usage: avc_to_rules.py <log>... > rules.cil
"""
import re
import sys
from collections import defaultdict

SRC = "pipa_port"
PAT = re.compile(r'denied\s+\{ ([^}]*)\}.*?scontext=u:r:' + SRC + r':s0\S* tcontext=u:(\w+):(\w+):s0\S* tclass=(\w+)')
PROC_READ = {"dir": {"search", "getattr", "read", "open"}, "file": {"read", "open", "getattr"}, "lnk_file": {"read", "getattr"}}

perms = defaultdict(set)
for path in sys.argv[1:]:
    for line in open(path, errors="replace"):
        m = PAT.search(line)
        if not m:
            continue
        p, role, t, c = m.groups()
        if role == "r" and t != SRC and c in PROC_READ and set(p.split()) <= PROC_READ[c]:
            continue  # /proc/<pid> scan: covered by the domain rules below
        perms[(t, c)].update(p.split())

print(";; /proc/<pid> of all processes (pgrep, pidof)")
for c, ps in PROC_READ.items():
    print(f"(allow {SRC} domain ({c} ({' '.join(sorted(ps))})))")
print(";; collected denials")
for (t, c), ps in sorted(perms.items()):
    t = "self" if t == SRC else t
    print(f"(allow {SRC} {t} ({c} ({' '.join(sorted(ps))})))")
