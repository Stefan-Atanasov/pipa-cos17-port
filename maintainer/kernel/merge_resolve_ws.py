#!/usr/bin/env python3
# After `git merge-file ours a/f b/f` (oppo_extract.sh KEEP= dirs): resolve conflicts whose "ours" side is only
# whitespace (unifdef -B squeezes blank lines in the OPPO base) by taking the OPPO block. Markers: -L ours ... -L oppo.
#   python3 merge_resolve_ws.py <file>...    prints the conflicts left per file
# Resolve git merge-file conflicts whose "ours" side is whitespace-only: keep OPPO's block (trimmed of blank edge
# lines) and the blank line ours had. Other conflicts are left untouched. Prints remaining count.
for p in sys.argv[1:]:
    lines = open(p).read().split('\n')
    out, i, left = [], 0, 0
    while i < len(lines):
        if lines[i].startswith('<<<<<<< ours'):
            j = i + 1; ours = []
            while not lines[j].startswith('======='): ours.append(lines[j]); j += 1
            k = j + 1; theirs = []
            while not lines[k].startswith('>>>>>>> oppo'): theirs.append(lines[k]); k += 1
            if all(not l.strip() for l in ours):
                t = theirs[:]
                while t and not t[0].strip(): t.pop(0)
                while t and not t[-1].strip(): t.pop()
                lead = [l for l in ours]  # keep ours' blank lines, put them after the block if theirs ended blank
                if theirs and not theirs[0].strip(): out += [''] if not ours else []
                out += t
                out += ours if ours else ([''] if theirs and not theirs[-1].strip() else [])
            else:
                out += lines[i:k+1]; left += 1
            i = k + 1
        else:
            out.append(lines[i]); i += 1
    open(p, 'w').write('\n'.join(out))
    print(left, p)
