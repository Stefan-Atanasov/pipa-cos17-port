#!/usr/bin/env python3
"""Diff the first and last snapshot of maintainer/battery/nightcap.sh: drain per hour, suspend count,
system sleep (aosd/cxsd), top wakeup sources, top IRQs, swap and kswapd/hybridswapd CPU.
    python3 -I nightcap_diff.py <dir with snap-N.txt> [first] [last]"""
import re, sys, glob, os
d = sys.argv[1]
fs = sorted(glob.glob(os.path.join(d, 'snap-*.txt')), key=lambda f: int(re.findall(r'\d+', os.path.basename(f))[0]))
a = fs[int(sys.argv[2])] if len(sys.argv) > 2 else fs[0]
b = fs[int(sys.argv[3])] if len(sys.argv) > 3 else fs[-1]
def parse(f):
    r = {'ws': {}, 'irq': {}, 'kv': {}, 'cpu': {}, 'sleep': {}}
    sec = None; mode = None
    for l in open(f, errors='replace'):
        l = l.rstrip('\n')
        if l.startswith('=='): sec = l; continue
        p = l.split()
        if not p: continue
        if p[0] == 'ws' and len(p) >= 6 and all(x.isdigit() for x in p[-4:]): r['ws'][' '.join(p[1:-4])] = list(map(int, p[-4:]))
        elif sec and 'irq' in sec and len(p) >= 3: r['irq'][p[0] + ' ' + p[-1]] = int(p[1])
        elif p[0] in ('cpu', 'kcpu') and len(p) >= 5: r['cpu'][p[2]] = int(p[3]) + int(p[4])
        elif sec and 'system_sleep' in sec:
            m = re.match(r'RPM Mode:(\w+)', l)
            if m: mode = m.group(1)
            m = re.search(r'count:(\d+)', l)
            if m and mode: r['sleep'][mode + '_count'] = int(m.group(1))
        elif sec and 'master_stats' in sec:
            if re.match(r'^[A-Z]', l): mode = l.strip()
            m = re.search(r'Sleep Accumulated Duration:0x([0-9a-f]+)', l)
            if m: r['sleep'][mode + '_acc_s'] = int(m.group(1), 16) / 19.2e6
            m = re.search(r'Sleep Count:0x([0-9a-f]+)', l)
            if m: r['sleep'][mode + '_count'] = int(m.group(1), 16)
        elif len(p) == 2 and re.match(r'^-?\d+(\.\d+)?$', p[1]): r['kv'][p[0]] = float(p[1])
        elif p[0] in ('pswpin', 'pswpout'): r['kv'][p[0]] = float(p[1])
    return r
A, B = parse(a), parse(b)
h = (B['kv']['date'] - A['kv']['date']) / 3600
print(f"{os.path.basename(a)} -> {os.path.basename(b)}: {h:.2f} h, uptime +{(B['kv']['uptime']-A['kv']['uptime'])/3600:.2f} h")
dc = (A['kv']['charge_counter'] - B['kv']['charge_counter']) / 1000
print(f"capacity {A['kv']['capacity']:.0f} -> {B['kv']['capacity']:.0f} % ({(A['kv']['capacity']-B['kv']['capacity'])/h:.2f} %/h), charge {dc:.0f} mAh = {dc/h:.1f} mAh/h")
print(f"suspends +{B['kv']['suspend_success']-A['kv']['suspend_success']:.0f}, fails +{B['kv']['suspend_fail']-A['kv']['suspend_fail']:.0f}")
for k in sorted(B['sleep']):
    if k in A['sleep']:
        dv = B['sleep'][k] - A['sleep'][k]
        print(f"  sleep {k}: +{dv:.0f}" + (f" ({dv/3600/h*100:.0f} % of wall)" if k.endswith('_acc_s') else ''))
print("top wakeup sources (wakeup_count, active_count, active ms):")
ws = []
for n, v in B['ws'].items():
    o = A['ws'].get(n, [0, 0, 0, 0])
    ws.append((v[2] - o[2], v[0] - o[0], v[3] - o[3], n))
for w in sorted(ws, key=lambda x: (x[0], x[2]), reverse=True)[:15]:
    if w[0] or w[2] > 1000: print(f"  {w[3]:<40} wake {w[0]:>5}  act {w[1]:>6}  {w[2]/1000:>8.1f} s")
print("top IRQs:")
iq = sorted(((v - A['irq'].get(n, 0), n) for n, v in B['irq'].items()), reverse=True)[:12]
for v, n in iq: print(f"  {n:<40} +{v}")
print(f"swap in/out pages: +{B['kv'].get('pswpin',0)-A['kv'].get('pswpin',0):.0f} / +{B['kv'].get('pswpout',0)-A['kv'].get('pswpout',0):.0f}")
for n, v in B['cpu'].items(): print(f"  cpu ticks {n}: +{v - A['cpu'].get(n, 0)}")
