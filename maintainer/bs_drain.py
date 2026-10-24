#!/usr/bin/env python3
"""Screen-off, unplugged drain per segment from batterystats history (charge counter).

    adb shell dumpsys batterystats > bs.txt; python3 -I bs_drain.py bs.txt

Prints each screen-off unplugged stretch of 1 h or more as net mAh/h and drops-only mAh/h (the gauge sometimes
jumps up; drops-only ignores that). Baselines: README "Idle drain" (53.4 before fixes, ~42 after).
"""
import re,sys,datetime as dt
scr=False;plug=False;seg=[];segs=[]
def close():
    global seg
    if len(seg)>=4: segs.append(seg)
    seg=[]
for l in open(sys.argv[1]):
    m=re.match(r'\s+(\d\d-\d\d \d\d:\d\d:\d\d)\.\d+ (\d{3}) (.*)',l)
    if not m: continue
    t=dt.datetime.strptime('2026-'+m[1],'%Y-%m-%d %H:%M:%S'); r=m[3]
    if '+screen' in r or '+plugged' in r or 'RESET' in l:
        close()
    if '+screen' in r: scr=True
    if '-screen' in r: scr=False
    if '+plugged' in r: plug=True
    if '-plugged' in r: plug=False
    c=re.search(r'charge=(\d+)',r)
    if c and not scr and not plug: seg.append((t,int(c[1]),int(m[2])))
close()
for s in segs:
    h=(s[-1][0]-s[0][0]).total_seconds()/3600
    if h<1: continue
    # sum only drops, ignore upward gauge jumps
    drop=sum(max(0,a[1]-b[1]) for a,b in zip(s,s[1:])); net=s[0][1]-s[-1][1]
    print(f"{s[0][0]:%m-%d %H:%M} -> {s[-1][0]:%m-%d %H:%M} {h:5.2f}h  net {net:4d} mAh = {net/h:5.1f} mAh/h | drops-only {drop/h:5.1f} mAh/h | level {s[0][2]}->{s[-1][2]}")
