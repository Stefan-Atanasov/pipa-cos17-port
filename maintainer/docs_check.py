#!/usr/bin/env python3
"""Check the public docs (docs/*.md) before a sync to the port repo. Read-only; exit 1 when an ERROR is found.

ERROR: a relative link that does not resolve, a docs/*.md file that the README doc map does not list, a private or
retired link (Google bug doc, PixelOS URL), a secret file name, the old flash prompt wording (y / Enter / N).
WARN:  an "Updated YYYY-MM-DD" date older than the current release, a doc that names an older release as current.
usage: python3 maintainer/docs_check.py
"""
import glob
import os
import re
import sys

COS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(COS, "docs")
# files that the sync script puts at the repo root next to docs/*.md
ROOT_EXTRA = {"RELEASE-NOTES.md", "CHANGELOG.md", "BUGS.md", "BLOBS.md", "LICENSE"}
NOT_IN_MAP = {"README.md", "CLAUDE.md", "CLAUDE-REFERENCE.md"}  # README is the map; CLAUDE*.md are linked from AGENTS

notes = sorted(glob.glob(os.path.join(COS, "RELEASE-NOTES-v*.md")))
notes = [n for n in notes if re.search(r"RELEASE-NOTES-v[0-9.]+\.md$", n)]
cur = max((re.search(r"v([0-9.]+)\.md$", n).group(1) for n in notes), key=lambda v: [int(x) for x in v.split(".")])
cur_text = open(os.path.join(COS, "RELEASE-NOTES-v%s.md" % cur)).read()
m = re.search(r"20[0-9]{2}-[0-9]{2}-[0-9]{2}", cur_text)
cur_date = m.group(0) if m else "0000-00-00"

errors, warns = [], []
names = {os.path.basename(p) for p in glob.glob(os.path.join(DOCS, "*.md"))}
readme = open(os.path.join(DOCS, "README.md")).read()

BAD = [
    (r"docs\.google\.com/document", "retired Google bug doc (use GitHub Issues)"),
    (r"https?://\S*pixelos\S*", "PixelOS URL (private build, memory rule)"),
    (r"keystore\.pass\s*[:=]|KSPASS=[^$\s]", "helper key password"),
    (r"answer `y`|\(\"y\"\)|press Enter in `FlashLinux|`N` in `FlashWindows", "old flash prompt (now 1 / 2 + ERASE)"),
]
for name in sorted(names):
    path = os.path.join(DOCS, name)
    text = open(path, encoding="utf-8").read()
    if name not in NOT_IN_MAP and "](%s)" % name not in readme:
        errors.append("%s: not in the README doc map" % name)
    for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", text):
        if re.match(r"[a-z]+:", target):
            continue
        t = target.split("?")[0]
        if t in names or t in ROOT_EXTRA or os.path.exists(os.path.join(COS, t)):
            continue
        errors.append("%s: link %s does not resolve" % (name, target))
    for n, line in enumerate(text.split("\n"), 1):
        for rx, why in BAD:
            if re.search(rx, line, re.I):
                errors.append("%s:%d: %s" % (name, n, why))
    for d in re.findall(r"Updated (20[0-9]{2}-[0-9]{2}-[0-9]{2})", text)[:1]:
        if d < cur_date:
            warns.append("%s: 'Updated %s' is older than v%s (%s)" % (name, d, cur, cur_date))
    for v in re.findall(r"(?:current|last|public) release \*{0,2}v([0-9.]+)", text, re.I):
        if v.rstrip(".") != cur:
            warns.append("%s: names v%s as the current release (now v%s)" % (name, v.rstrip("."), cur))

# helper 3.3 update check: docs/latest.json must name the current release, its date and its build (ptNNN in the notes)
import json
try:
    lj = json.load(open(os.path.join(DOCS, "latest.json")))
    if str(lj.get("version", "")).endswith(" test"):
        # 2026-11-26 (user): between releases latest.json may name the tester build ("pt167 test", OTA for testers;
        # only helpers of test builds read it). It must be newer than the release and carry an ota block.
        if not isinstance(lj.get("build"), int) or "ota" not in lj:
            errors.append("latest.json: test entry without build or ota block")
        if cur != "9.3":
            # from v9.4 on every user's helper reads latest.json: tester builds go to latest-test.json (helper 3.7)
            errors.append("latest.json names a tester build, but v%s users read it: latest.json = SourceForge releases only" % cur)
        warns.append("latest.json names the tester build %s (not the release v%s)" % (lj.get("version"), cur))
    elif lj.get("version") != "v" + cur or lj.get("date") != cur_date:
        errors.append("latest.json: %s %s, current release is v%s %s" % (lj.get("version"), lj.get("date"), cur, cur_date))
    if not str(lj.get("version", "")).endswith(" test") and (not isinstance(lj.get("build"), int)
                                                          or ("pt%d" % lj["build"]) not in cur_text):
        errors.append("latest.json: build %r is not in RELEASE-NOTES-v%s.md" % (lj.get("build"), cur))
except (OSError, ValueError) as e:
    errors.append("latest.json: %s" % e)

print("current release: v%s (%s), %d docs" % (cur, cur_date, len(names)))
for w in warns:
    print("WARN  " + w)
for e in errors:
    print("ERROR " + e)
print("%d errors, %d warnings" % (len(errors), len(warns)))
sys.exit(1 if errors else 0)
