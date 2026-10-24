#!/usr/bin/env python3
# Check that every hunk of diff(a -> b) (oppo_extract.sh KEEP= dirs) landed intact in the merged tree, with context.
#   (cd <keep>/b && find . -type f | sed "s|^\./||") | python3 verify_merge.py <keep>/a <keep>/b <tree>
# A brace that sits in OPPO base context but not in ours shows up as a compile error instead (percpu-rwsem case).
# For each file: every hunk of diff(a -> b) must be present in merged: its added lines as a contiguous block
# (ignoring whitespace), and its deleted lines must not sit right before/after where the block landed.
A, B, M = sys.argv[1:4]
files = [l.strip() for l in sys.stdin if l.strip()]
norm = lambda l: ''.join(l.split())
bad = 0
for f in files:
    a = open(os.path.join(A, f)).read().split('\n'); b = open(os.path.join(B, f)).read().split('\n')
    m = open(os.path.join(M, f)).read().split('\n'); mn = [norm(x) for x in m]
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal': continue
        add = [norm(x) for x in b[j1:j2] if norm(x)]
        pre = [norm(x) for x in b[max(0, j1-4):j1] if norm(x)][-1:]
        post = [norm(x) for x in b[j2:j2+4] if norm(x)][:1]
        dele = [norm(x) for x in a[i1:i2] if norm(x)]
        if not add and dele:
            # pure deletion in OPPO: check the deleted lines are gone (approximate: the block must not exist)
            n = len(dele)
            if any(mn[k:k+n] == dele for k in range(len(mn))):
                print(f"{f}: OPPO deleted lines still present near a:{i1+1}: {dele[:2]}"); bad += 1
            continue
        if not add: continue
        n = len(add); mm = [x for x in mn]
        # find add block in merged allowing blank lines between
        mnb = [(k, x) for k, x in enumerate(mn) if x]
        seq = [x for _, x in mnb]
        blk = pre + add + post
        found = [k + len(pre) for k in range(len(seq) - len(blk) + 1) if seq[k:k+len(blk)] == blk]
        if not found and [k for k in range(len(seq) - n + 1) if seq[k:k+n] == add]:
            print(f"{f}: OPPO hunk b:{j1+1}-{j2} present but its context differs (check by hand): {add[0][:60]}"); bad += 1; continue
        if not found:
            print(f"{f}: OPPO hunk b:{j1+1}-{j2} not found intact: first={add[0][:70]}"); bad += 1; continue
        if dele:
            # replaced lines must not directly precede/follow the inserted block
            ok = True
            for k in found:
                before = seq[max(0, k-len(dele)):k]; after = seq[k+n:k+n+len(dele)]
                if before == dele or after == dele: ok = False
            if not ok:
                print(f"{f}: OPPO replaced lines still present at b:{j1+1}: {dele[:2]}"); bad += 1
print("problems:", bad)
