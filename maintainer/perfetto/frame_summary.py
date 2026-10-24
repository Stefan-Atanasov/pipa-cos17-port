#!/usr/bin/env python3
"""Visible-stutter summary of FrameTimeline traces (traced_heavy.sh): SF frames by jank type, launcher janky /
Buffer Stuffing / App Deadline, DRM atomic commits > 4 ms.  usage: frame_summary.py <trace> [...]"""
import sys
from perfetto.trace_processor import TraceProcessor
for f in sys.argv[1:]:
    tp=TraceProcessor(trace=f); q=lambda s: list(tp.query(s))
    sf=q("select upid from process where name like '%surfaceflinger%' limit 1")[0].upid
    la=q("select upid from process where name='com.android.launcher' limit 1")[0].upid
    tot=q(f"select count(*) n from actual_frame_timeline_slice where upid={sf}")[0].n
    sfj=q(f"""select jank_type j, count(*) n from actual_frame_timeline_slice where upid={sf} group by j order by n desc limit 6""")
    lat=q(f"select count(*) n, sum(jank_type!='None') j, sum(jank_type like '%Buffer Stuffing%') bs, sum(jank_type like '%App Deadline%') app from actual_frame_timeline_slice where upid={la}")[0]
    lc=q("select count(*) n, sum(dur)/1e6 ms from slice where name='DRMAtomicReq::Commit::' and dur>4e6")[0]
    span=q("select (max(ts)-min(ts))/1e9 s from actual_frame_timeline_slice")[0].s
    print('==',f.split('/')[-1],f'span {span:.0f}s')
    print(f'  SF frames {tot}: '+', '.join(f'{r.j} {r.n}' for r in sfj))
    print(f'  launcher frames {lat.n}: janky {lat.j} ({100*lat.j/lat.n:.0f}%), BufferStuffing {lat.bs}, AppDeadline {lat.app}')
    print(f'  long DRM commits (>4ms) {lc.n}, {lc.ms:.0f} ms')
    tp.close()
