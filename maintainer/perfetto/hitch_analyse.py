#!/usr/bin/env python3
"""Where did the CPU go in a manual trace? Long frames per app, long D waits (freezer bursts vs I/O), main-thread states of
launcher/systemui, top CPU users around the worst hitches, kswapd per core, prime-core users, idle per core.
   ~/Documents/pipa/port-work/perfetto-venv/bin/python -I hitch_analyse.py <trace.pftrace>"""
import sys
from collections import Counter
from perfetto.trace_processor import TraceProcessor
tp = TraceProcessor(trace=sys.argv[1]); q = lambda s: list(tp.query(s))
t0 = q("select trace_start() s")[0].s
span = q("select (trace_end()-trace_start())/1e9 s")[0].s
print(f"span {span:.0f} s")
print("== long frames (>120 ms) per app")
lf = q(f"""select p.name pr, (a.ts-{t0})/1e9 s, a.dur/1e6 ms from actual_frame_timeline_slice a join process p using(upid)
  where a.dur > 120e6""")
for pr, n in Counter(r.pr for r in lf).most_common(10):
    rs = [r for r in lf if r.pr == pr]
    print(f"  {pr[:38]:38} {n:3}  max {max(r.ms for r in rs):5.0f} ms  at s {sorted(set(int(r.s) for r in rs))}")
print("== D waits > 150 ms (bursts = many threads of one process at the same instant = freezer)")
d = q(f"""select (ts-{t0})/1e9 s, dur/1e6 ms, p.name pr, io_wait io from thread_state ts join thread t using(utid)
  left join process p using(upid) where state='D' and dur > 150e6""")
burst = Counter((r.pr, round(r.s, 1)) for r in d)
b = sum(n for k, n in burst.items() if n >= 3)
print(f"  total {len(d)}, in bursts {b}, scattered {len(d)-b}, io_wait=1: {sum(1 for r in d if r.io)}")
for r in sorted([r for r in d if burst[(r.pr, round(r.s, 1))] < 3], key=lambda r: -r.ms)[:8]:
    print(f"  {r.s:6.1f}s {r.ms:5.0f} ms io={r.io} {(r.pr or '?')[:40]}")
print("== main thread states, whole trace (s)")
for r in q(f"""select p.name, ts.state st, sum(ts.dur)/1e9 s from thread_state ts join thread t using(utid) join process p using(upid)
  where t.tid=p.pid and p.name in ('com.android.launcher','com.android.systemui') group by 1,2 order by 1, 3 desc"""):
    print(f"  {r.name[-9:]:9} {r.st:8} {r.s:6.1f}")
hit = Counter(int(r.s) for r in lf).most_common(3)
for sec, n in hit:
    print(f"== CPU use {sec-1}-{sec+1}s ({n} long frames): top processes, cpu-ms by cluster little/big/prime")
    for r in q(f"""select coalesce(p.name, t.name) pr, sum(case when s.cpu<=3 then s.dur end)/1e6 l,
      sum(case when s.cpu between 4 and 6 then s.dur end)/1e6 b, sum(case when s.cpu=7 then s.dur end)/1e6 pm, sum(s.dur)/1e6 tot
      from sched s join thread t using(utid) left join process p using(upid)
      where s.ts-{t0} between {sec-1}e9 and {sec+1}e9 and t.tid != 0 group by pr order by tot desc limit 8"""):
        print(f"  {(r.pr or '?')[:34]:34} {r.l or 0:6.0f} {r.b or 0:6.0f} {r.pm or 0:6.0f}")
print("kswapd cpu-s by cpu:", [(r.cpu, round(r.s, 1)) for r in q("""select s.cpu, sum(s.dur)/1e9 s from sched s join thread t using(utid)
  where t.name like 'kswapd%' group by s.cpu order by s.cpu""")])
print("prime core (cpu7) top users s:", [(r.n[:22], round(r.s, 1)) for r in q("""select coalesce(p.name, t.name) n, sum(s.dur)/1e9 s
  from sched s join thread t using(utid) left join process p using(upid) where s.cpu=7 and t.tid!=0 group by n order by s desc limit 6""")])
print("idle s by cpu:", [(r.cpu, round(r.s, 1)) for r in q("""select s.cpu, sum(s.dur)/1e9 s from sched s join thread t using(utid)
  where t.tid=0 group by s.cpu order by s.cpu""")])
