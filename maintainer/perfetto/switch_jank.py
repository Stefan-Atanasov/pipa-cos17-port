#!/usr/bin/env python3
"""switch_jank.py: do jank frames cluster around display refresh-rate switches / transition ends?
How: switches = value changes of the SurfaceFlinger counter ActiveModeFps*; transitions = 'PerfSession-d0-Transition'
slices (start..end); jank = actual_frame_timeline_slice (all apps + SF) with jank_type, "real" = not only Buffer Stuffing/Non Animating.
Tables: jank density near (+-100/300 ms) vs outside switches, and 0-300 ms after transition end with/without a switch inside.
Usage: /home/stefan/Documents/pipa/port-work/perfetto-venv/bin/python -I switch_jank.py trace1.pftrace [trace2 ...]"""
import sys, bisect
from collections import Counter
from perfetto.trace_processor import TraceProcessor

def union(iv, lo, hi):
    out = []
    for a, b in sorted((max(a, lo), min(b, hi)) for a, b in iv):
        if b <= a: continue
        if out and a <= out[-1][1]: out[-1][1] = max(out[-1][1], b)
        else: out.append([a, b])
    return out

def inside(ts, iv):  # iv: merged sorted list
    i = bisect.bisect_right([a for a, _ in iv], ts) - 1
    return i >= 0 and ts < iv[i][1]

def real(j):
    parts = {p.strip() for p in j.split(',')}
    return bool(parts - {'None', 'Buffer Stuffing', 'Non Animating'})

def row(name, frames, jk, secs):
    r = 100 * jk / frames if frames else 0
    d = jk / secs if secs else 0
    return f'  {name:<34}{secs:8.2f} s {frames:7d} fr {jk:6d} jank {r:6.1f} % {d:7.2f} /s'

def analyse(path):
    tp = TraceProcessor(trace=path); q = lambda s: list(tp.query(s))
    t0 = q("select min(ts) t from actual_frame_timeline_slice")[0].t
    t1 = q("select max(ts+dur) t from actual_frame_timeline_slice")[0].t
    # --- rate switches
    cs = q("select c.ts, c.value from counter c join counter_track t on c.track_id=t.id where t.name like 'ActiveModeFps%' order by c.ts")
    sw, prev = [], None
    for c in cs:
        v = int(round(c.value))
        if prev is not None and v != prev and c.ts >= t0: sw.append((c.ts, prev, v))
        prev = v
    types = Counter(f'{a}->{b}' for _, a, b in sw)
    # --- transitions
    tr = [(r.ts, r.ts + r.dur) for r in q("select ts,dur from slice where name='PerfSession-d0-Transition' order by ts")]
    # --- frames
    fr = q("""select a.ts, a.dur, a.jank_type j, p.name pn from actual_frame_timeline_slice a left join process p using(upid)
              where a.ts>=%d""" % t0)
    def cat(n):
        if n is None: return 'other'
        if 'surfaceflinger' in n: return 'SF'
        if n == 'com.android.launcher': return 'launcher'
        if n == 'com.android.systemui': return 'systemui'
        return 'apps'
    frames = [(f.ts, f.j != 'None', real(f.j), cat(f.pn), 'ModeChange' in f.j) for f in fr]
    span = (t1 - t0) / 1e9
    name = path.split('/')[-1]
    print(f'\n===== {name}  span {span:.1f} s, {len(frames)} frames, jank(any) {sum(f[1] for f in frames)}, real {sum(f[2] for f in frames)}')
    print(f'switches: {len(sw)}  ' + ', '.join(f'{k} x{n}' for k, n in sorted(types.items())))
    print('  switch times (s): ' + ' '.join(f'{(t-t0)/1e9:.1f}:{a}>{b}' for t, a, b in sw))
    print(f'transitions: {len(tr)}; SF-flagged "ModeChange in progress" frames: {sum(f[4] for f in frames)}')
    for label, sel in (('ALL frames', lambda f: True), ('SF only', lambda f: f[3] == 'SF'),
                       ('launcher', lambda f: f[3] == 'launcher'), ('systemui', lambda f: f[3] == 'systemui'), ('apps', lambda f: f[3] == 'apps')):
        fs = [f for f in frames if sel(f)]
        print(f'\n[{label}] real jank (excl. Buffer Stuffing/Non Animating)    window  frames  jank  jank/fr  jank/s')
        for w in (100, 300):
            iv = union([(t - w * 1000000, t + w * 1000000) for t, _, _ in sw], t0, t1)
            near = sum(b - a for a, b in iv) / 1e9
            n_in = [f for f in fs if inside(f[0], iv)]
            n_out = len(fs) - len(n_in)
            j_in = sum(f[2] for f in n_in); j_out = sum(f[2] for f in fs) - j_in
            print(row(f'within +-{w} ms of switch', len(n_in), j_in, near))
            print(row(f'outside', n_out, j_out, span - near))
    # --- after transition end
    print('\n[ALL frames] 0-300 ms after transition end (real jank)')
    ivs = {True: [], False: []}
    for s, e in tr:
        has = any(e <= t < e + 300000000 for t, _, _ in sw)
        ivs[has].append((e, e + 300000000))
    for has, lab in ((True, 'with switch inside'), (False, 'without switch')):
        iv = union(ivs[has], t0, t1)
        n = [f for f in frames if inside(f[0], iv)]
        print(row(f'{lab} (n={len(ivs[has])})', len(n), sum(f[2] for f in n), sum(b - a for a, b in iv) / 1e9))
    allt = union([(e, e + 300000000) for _, e in tr], t0, t1)
    rest = sum(b - a for a, b in allt) / 1e9
    nin = [f for f in frames if not inside(f[0], allt)]
    print(row('everything else (not post-transition)', len(nin), sum(f[2] for f in nin), span - rest))
    # per-switch relation to transition end
    rel = []
    for t, a, b in sw:
        d = [(t - e) / 1e6 for _, e in tr if abs(t - e) < 1e9]
        rel.append(min(d, key=abs) if d else None)
    near_end = sum(1 for d in rel if d is not None and 0 <= d <= 300)
    print(f'  switches within 0-300 ms after a transition end: {near_end}/{len(sw)}; within +-1 s of one: {sum(d is not None for d in rel)}/{len(sw)}')
    tp.close()

for p in sys.argv[1:]:
    analyse(p)
