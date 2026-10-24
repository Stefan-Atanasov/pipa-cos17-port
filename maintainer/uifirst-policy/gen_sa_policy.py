# Build the system_ext CIL block for OPPO's sched_assist/frame boost proc nodes from the donor's vendor rules.
#   python3 -I gen_sa_policy.py sa_rules.cil <our cil files...>  > block.cil
import re, sys
rules = open(sys.argv[1]).read().splitlines()
known = set()
for f in sys.argv[2:]:
    for m in re.finditer(r'^\((?:type|typeattribute) ([^ ()]+)\)', open(f, errors='replace').read(), re.M):
        known.add(m.group(1))
# our new types (declared by us; donor vendor declares them) and the nodes our kernel has
NEW = ['oplus_scheduler_sched_assist_proc', 'oplus_ux_task_app_proc', 'oplus_imflag_app_proc',
       'proc_frame_boost_sys_ctrl', 'proc_fbg_sysctl', 'oplus_sched_assist_proc', 'oplus_sched_assist_scene_proc']
GENFS = {'/oplus_scheduler/sched_assist', '/oplus_scheduler/sched_assist/ux_task_app',
         '/oplus_scheduler/sched_assist/im_flag_app', '/oplus_frame_boost/sys_ctrl',
         '/sys/kernel/sched_assist_enabled', '/sys/kernel/sched_assist_scene',
         '/sys/fbg/frame_boost_enabled', '/sys/fbg/input_boost_enabled', '/sys/fbg/slide_boost_enabled',
         '/sys/fbg/frame_boost_debug'}
out = ['', ';; ================= pipa port 2i: OPPO UI First proc nodes (our WALT kernel, branch oppo) =========',
       ';; Types, labels and rules as in the donor (OPD2515 C.06) vendor policy, whose vendor we do not ship.']
for t in NEW:
    if t in known:
        sys.exit(f'{t} already declared')
    out += [f'(type {t})', f'(roletype object_r {t})']
out.append('(typeattributeset proc_type (%s))' % ' '.join(NEW))
out.append('(typeattributeset fs_type (%s))' % ' '.join(NEW))
out.append('(typeattributeset mlstrustedobject (%s))' % ' '.join(NEW))
seen = set(); skipped = set()
for l in rules:
    m = re.match(r'^\(genfscon proc "([^"]+)" \(u object_r ([^ ]+) ', l)
    if m:
        if m.group(1) in GENFS and m.group(2) in NEW:
            out.append(l)
        continue
    m = re.match(r'^\((allow|allowx) ([^ ]+) ([^ ]+) (.*)\)$', l)
    if not m:
        continue
    src = re.sub(r'_202504$', '', m.group(2)); tgt = m.group(3)
    if tgt not in NEW:
        continue
    if src not in known:
        skipped.add(src); continue
    r = f'({m.group(1)} {src} {tgt} {m.group(4)})'
    if r not in seen:
        seen.add(r); out.append(r)
print('\n'.join(out))
print(f';; skipped (domain not in this ROM/vendor): {" ".join(sorted(skipped))}', file=sys.stderr)
