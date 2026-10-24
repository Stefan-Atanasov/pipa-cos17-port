#!/usr/bin/env python3
"""Why are frames late? Analyse a perfetto trace recorded with jank.cfg.
   ~/Documents/pipa/port-work/perfetto-venv/bin/python -I analyse.py <trace.pftrace> [process substrings...]
For each process (default launcher, systemui): FrameTimeline jank types, then, over the janky frames' expected-to-actual
windows, where the main thread and RenderThread spent their time: running on little (0-3) / big (4-6) / prime (7)
cores, runnable (waiting for a CPU = scheduler), sleeping (S: lock/binder/wait), D (I/O); average CPU frequency while
running; top blocked-reason functions and the binder destinations of the main thread.
Without FrameTimeline (atrace text traces: traced does not start on this ROM) a frame = main-thread
Choreographer#doFrame start to the end of the next RenderThread DrawFrame; late = longer than LATE_MS (2 vsyncs at
144 Hz)."""
LATE_MS = 13.9
import sys
from perfetto.trace_processor import TraceProcessor

trace = sys.argv[1]
procs = sys.argv[2:] or ["com.android.launcher", "com.android.systemui"]
import os
# TP_ADDR=localhost:9001 reuses a running `trace_processor_shell -D <trace>` (a 600 MB text trace takes minutes to load)
tp = TraceProcessor(addr=os.environ["TP_ADDR"]) if os.environ.get("TP_ADDR") else TraceProcessor(trace=trace)
q = lambda s: list(tp.query(s))

def cluster(cpu):
    return "little" if cpu <= 3 else ("big" if cpu <= 6 else "prime")

for name in procs:
    p = q(f"select upid, name from process where name like '%{name}%' order by upid limit 1")
    if not p:   # atrace text has no process names: match the main thread's comm (last 15 chars of the name)
        p = q(f"""select t.upid, '{name}' name from thread t join process using(upid)
                 where t.tid = process.pid and t.name = '{name[-15:]}' limit 1""")
    if not p:
        print(f"== {name}: not in trace"); continue
    upid = p[0].upid
    print(f"== {p[0].name}")
    tot = q(f"select count(*) n from actual_frame_timeline_slice where upid={upid}")[0].n
    rows = q(f"""select jank_type, count(*) n, avg(dur)/1e6 ms from actual_frame_timeline_slice
                where upid={upid} group by jank_type order by n desc""")
    print(f"  frames {tot}:", ", ".join(f"{r.jank_type} {r.n} ({r.ms:.1f} ms)" for r in rows))
    # janky frames (app side): window = [expected start, actual end]
    jank = q(f"""select a.ts, a.dur, a.display_frame_token tok from actual_frame_timeline_slice a
                where a.upid={upid} and a.jank_type like '%App Deadline Missed%'""")
    utids = {r.tname: r.utid for r in q(f"""select utid, case when tid=pid then 'main' else thread.name end tname from thread
             join process using(upid) where upid={upid} and (tid=pid or thread.name='RenderThread')""")}
    if not tot and "main" in utids and "RenderThread" in utids:
        fr = q(f"""select d.ts, (select min(r.ts + r.dur) from slice r join thread_track tt on r.track_id=tt.id
                   where tt.utid={utids['RenderThread']} and r.name like 'DrawFrame%' and r.ts >= d.ts) - d.ts dur
                   from slice d join thread_track t on d.track_id=t.id
                   where t.utid={utids['main']} and d.name like 'Choreographer#doFrame%'""")
        fr = [f for f in fr if f.dur]
        jank = [f for f in fr if f.dur > LATE_MS * 1e6]
        ds = sorted(f.dur / 1e6 for f in fr)
        if ds:
            print(f"  frames {len(ds)} (doFrame->DrawFrame end): late >{LATE_MS} ms {len(jank)} ({100 * len(jank) / len(ds):.1f}%),"
                  f" p50 {ds[len(ds) // 2]:.1f} p90 {ds[int(len(ds) * .9)]:.1f} p99 {ds[int(len(ds) * .99)]:.1f} ms")
    if not jank:
        continue
    for tn, utid in utids.items():
        agg = {}
        freq_w = freq_t = 0
        for f in jank:
            t0, t1 = f.ts, f.ts + f.dur
            for s in q(f"""select ts, dur, state, cpu, io_wait from thread_state where utid={utid}
                         and ts < {t1} and ts + dur > {t0}"""):
                d = min(s.ts + s.dur, t1) - max(s.ts, t0)
                if s.state == "Running":
                    k = "run-" + cluster(s.cpu)
                    fr = q(f"""select value from counter c join cpu_counter_track t on c.track_id=t.id
                              where t.name='cpufreq' and t.cpu={s.cpu} and c.ts <= {max(s.ts, t0)}
                              order by c.ts desc limit 1""")
                    if fr:
                        freq_w += fr[0].value * d; freq_t += d
                elif s.state in ("R", "R+"):
                    k = "runnable"
                elif s.state == "S":
                    k = "sleep"
                elif s.state.startswith("D"):
                    k = "D(io)" if s.io_wait else "D"
                else:
                    k = s.state
                agg[k] = agg.get(k, 0) + d
        tot_ns = sum(agg.values()) or 1
        parts = ", ".join(f"{k} {100 * v / tot_ns:.0f}%" for k, v in sorted(agg.items(), key=lambda x: -x[1]))
        fq = f", avg freq {freq_w / freq_t / 1e3:.0f} MHz" if freq_t else ""
        print(f"  {tn} in {len(jank)} late frames: {parts}{fq}")
    main = utids.get("main")
    if main is not None:
        rows = [] if not q("select 1 from sqlite_master where name='sched_blocked_reason'") else q(f"""select ifnull(s.function, '?') fn, sum(t.dur)/1e6 ms from thread_state t
                    left join sched_blocked_reason s on s.utid=t.utid and s.ts between t.ts and t.ts + t.dur
                    where t.utid={main} and t.state like 'D%' group by fn order by ms desc limit 5""")
        if rows:
            print("  main D-state:", ", ".join(f"{r.fn} {r.ms:.0f} ms" for r in rows))
        try:   # needs the android.binder stdlib module (newer trace processors)
            q("INCLUDE PERFETTO MODULE android.binder")
            rows = q(f"""select ifnull(rp.name, '?') dst, count(*) n, sum(b.dur)/1e6 ms from android_binder_txns b
                    left join process rp on rp.upid = b.server_upid
                    where b.client_utid={main} and b.is_sync group by dst order by ms desc limit 5""")
        except Exception:
            rows = []
        if rows:
            print("  main sync binder:", ", ".join(f"{r.dst} {r.n}x {r.ms:.0f} ms" for r in rows))

# CPU/GPU frequency residency over the whole trace
print("== cpufreq residency (time-weighted MHz, % at max) by cluster")
for cpu in (0, 4, 7):
    r = q(f"""select sum(value * dur) / sum(dur) / 1e3 mhz, max(value) / 1e3 mx,
             sum(case when value = (select max(value) from counter c2 join cpu_counter_track t2 on c2.track_id=t2.id
                 where t2.name='cpufreq' and t2.cpu={cpu}) then dur else 0 end) * 100.0 / sum(dur) pmax
             from (select value, lead(ts) over (order by ts) - ts dur from counter c join cpu_counter_track t
                   on c.track_id=t.id where t.name='cpufreq' and t.cpu={cpu}) where dur is not null""")
    if r and r[0].mhz:
        print(f"  cpu{cpu} ({cluster(cpu)}): avg {r[0].mhz:.0f} MHz, max {r[0].mx:.0f}, {r[0].pmax:.0f}% at max")
r = q("""select sum(value * dur) / sum(dur) / 1e6 mhz from (select value, lead(ts) over (order by ts) - ts dur
        from counter c join gpu_counter_track t on c.track_id=t.id where t.name like 'gpufreq%') where dur is not null""")
if r and r[0].mhz:
    print(f"  gpu: avg {r[0].mhz:.0f} MHz")
