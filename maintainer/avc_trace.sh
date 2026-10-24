#!/bin/sh
# Capture SELinux denials on the pipa kernel, which cannot log them itself.
#
#   sh avc_trace.sh start            arm the probes (live only; gone after a reboot)
#   sh avc_trace.sh dump [label]     resolve and save the denials seen since start
#   sh avc_trace.sh stop             remove the probes
#   ADB="adb -s 83836a90" sh avc_trace.sh ...    (USB instead of the default TCP serial)
#
# Why: the running kernel (4.19.325-cip136-st20-N0-kernel++) is built without the audit core
# (/proc/kallsyms has no audit_log_start/kauditd; /proc/config.gz claiming CONFIG_AUDIT=y is
# stale). SELinux still decides every denial, but the record is dropped, so no AVC reaches dmesg
# or logcat, and logd's audit listener fails at boot ("SocketListener: Failed to start unbound
# listener"). The RE404 kernel in COS17/kernel/ lacks the audit core too.
#
# How: ftrace kprobes (kprobe_events works, again unlike the config.gz claim).
#  - avc:  slow_avc_audit(state, ssid, tsid, tclass, requested, audited, denied, result, ad, flags)
#          fires for every denial that would be logged (dontaudit rules already applied).
#          ad->type 9 (inode) gives the inode number; 1/10/12 (path/dentry/file) the name.
#  - cav/ccav: the avc passes the kernel's own class number (its built-in classmap order), not the
#          policy's. On each AVC miss security_compute_av(.., orig_tclass) calls
#          context_struct_compute_av(.., policy tclass) in the same task; the pairs give the map,
#          cached in port-work/avc/classmap-<kernel>.tsv. Perm bits follow the policy's order
#          (same as the kernel's for the classes checked: file read=0x2, dir watch_with_perm).
#  - sidq/sidm: security_sid_to_context_core(sid) followed by mls_sid_to_context in the same task;
#          at that point x21 holds the "user:role:type" buffer (found by register dump on this
#          kernel build; a self-test checks it). String fetches fault on this kernel, so strings
#          are read as raw u64 words and decoded on the host.
# SIDs are resolved by seeding: reading every process context and `ls -Z` over the main trees.
# Unknown SIDs stay numeric. result=-13 means enforced; result=0 with a denial means permissive.
set -eu
ADB=${ADB:-adb -s 192.168.0.37:5555}
CMD=${1:-}; LABEL=${2:-run}
OUT=~/Documents/pipa/port-work/avc
$ADB get-state >/dev/null || { echo "no device on: $ADB"; exit 1; }

dev() { $ADB shell "su -c 'sh -s'" ; }

case $CMD in
start)
dev <<'DEVICE'
T=/sys/kernel/tracing
A='+0($stack)'
N() { echo "$1a=+0(+0x28($2)):x64 $1b=+8(+0x28($2)):x64 $1c=+16(+0x28($2)):x64 $1d=+24(+0x28($2)):x64"; }
W() { i=0; s=; while [ $i -lt 10 ]; do s="$s w$i=+$((i*8))(%x21):x64"; i=$((i+1)); done; echo "$s"; }
for i in pipa_avc pipa_sid; do [ -d $T/instances/$i ] && { echo 0 > $T/instances/$i/events/enable; rmdir $T/instances/$i; }; done
for e in avc sidq sidm cav ccav; do echo 0 > $T/events/kprobes/$e/enable 2>/dev/null; echo "-:$e" >> $T/kprobe_events 2>/dev/null; done
echo "p:avc slow_avc_audit ssid=%x1:u32 tsid=%x2:u32 tclass=%x3:u16 req=%x4:x32 denied=%x6:x32 result=%x7:s32 ty=+0($A):u8 ino=+0x40(+8($A)):u64 $(N p "+0x10($A)") $(N d "+8($A)") $(N f "+0x18(+8($A))")" >> $T/kprobe_events
echo "p:sidq security_sid_to_context_core sid=%x1:u32" >> $T/kprobe_events
echo "p:sidm mls_sid_to_context $(W)" >> $T/kprobe_events
echo "p:cav security_compute_av tclass=%x3:u16" >> $T/kprobe_events
echo "p:ccav context_struct_compute_av tclass=%x3:u16" >> $T/kprobe_events
mkdir $T/instances/pipa_avc $T/instances/pipa_sid
echo 4096 > $T/instances/pipa_avc/buffer_size_kb
echo 4096 > $T/instances/pipa_sid/buffer_size_kb
echo "denied != 0" > $T/instances/pipa_avc/events/kprobes/avc/filter
echo 1 > $T/instances/pipa_avc/events/kprobes/avc/enable
echo 1 > $T/instances/pipa_sid/events/kprobes/sidq/enable
echo 1 > $T/instances/pipa_sid/events/kprobes/sidm/enable
echo 1 > $T/instances/pipa_sid/events/kprobes/cav/enable
echo 1 > $T/instances/pipa_sid/events/kprobes/ccav/enable
echo armed
DEVICE
    echo "Probes armed until reboot or 'stop'. Use the tablet, then: sh $0 dump <label>" ;;
dump)
    mkdir -p "$OUT"; F=$OUT/$(date +%Y%m%d-%H%M)-$LABEL
    dev > "$F.raw" <<'DEVICE'
T=/sys/kernel/tracing
[ -d $T/instances/pipa_avc ] || { echo "NOT ARMED"; exit 1; }
# seed the SID map: process contexts, then file contexts of the main trees
cat /proc/[0-9]*/attr/current >/dev/null 2>&1
for d in /dev /vendor /odm /system_ext /system/bin /system/etc /product /data /data/vendor \
         /data/vendor_de /data/misc /data/system /data/local /mnt /metadata /persist /sys/class \
         /sys/class/power_supply /proc /sys/fs/selinux /sys/kernel; do
    ls -Za $d >/dev/null 2>&1
done
find /dev /vendor/bin /odm/bin /system_ext/bin /sys/class/power_supply /sys/class/input \
     -maxdepth 3 2>/dev/null | xargs ls -Zd >/dev/null 2>&1
ls -Zd /system/bin/sh >/dev/null
echo "#### avc"; grep -v '^#' $T/instances/pipa_avc/trace
echo "#### sid"; grep -v '^#' $T/instances/pipa_sid/trace
echo > $T/instances/pipa_sid/trace
echo "#### kernel $(uname -r)"
echo "#### ctx"; for p in /proc/[0-9]*; do echo "${p#/proc/} $(cat $p/attr/current 2>/dev/null)"; done
echo "#### class"
for c in /sys/fs/selinux/class/*; do
    printf '%s %s' "$(cat $c/index)" "${c##*/}"
    for p in $c/perms/*; do printf ' %s=%s' "${p##*/}" "$(cat $p)"; done; echo
done
DEVICE
    grep -q '^NOT ARMED' "$F.raw" && { echo "not armed: run 'sh $0 start' first"; exit 1; }
    python3 -I - "$F.raw" "$OUT" > "$F.txt" <<'PY'
import re, struct, sys, collections
sec = collections.defaultdict(list); cur = None
for l in open(sys.argv[1], errors='replace'):
    l = l.rstrip('\n')
    if l.startswith('#### '): cur = l[5:]; sec[cur]; continue
    if cur: sec[cur].append(l)
head = re.compile(r'^\s*(.+)-(\d+)\s+\[\d+\]\s+\S+\s+([\d.]+):\s+(\w+):')
def fields(l): return dict(re.findall(r'(\w+)=(\S+)', l))
def words(d, keys):
    try: b = b''.join(struct.pack('<Q', int(d[k], 16)) for k in keys)
    except (KeyError, ValueError): return ''
    s = b.split(b'\0')[0]
    return s.decode() if s and all(32 < c < 127 for c in s) else ''
# SID map from sidq -> sidm pairs in the same task
sid, last, lastc, kmap = {}, {}, {}, {}
for l in sec['sid']:
    m = head.match(l)
    if not m: continue
    pid, ev, d = m.group(2), m.group(4), fields(l)
    if ev == 'cav': lastc[pid] = int(d['tclass'])
    elif ev == 'ccav' and pid in lastc: kmap[lastc.pop(pid)] = int(d['tclass'])
    elif ev == 'sidq': last[pid] = d.get('sid')
    elif ev == 'sidm' and pid in last:
        s = words(d, ['w%d' % i for i in range(10)])
        if s: sid[int(last.pop(pid))] = s + ':s0'
ok = 'u:object_r:shell_exec' in ''.join(sid.values())
ctx = {}
for l in sec['ctx']:
    p = l.split(' ', 1)
    if len(p) == 2 and p[1]: ctx[p[0]] = p[1].strip()
cls = {}
for l in sec['class']:
    p = l.split();
    if len(p) < 2: continue
    perms = {}
    for kv in p[2:]:
        k, v = kv.split('=', 1); perms[1 << (int(v) - 1)] = k
    cls[int(p[0])] = (p[1], perms)
def permnames(c, mask):
    names = [n for b, n in sorted(byname.get(c, ('', {}))[1].items()) if mask & b]
    return ' '.join(names) if names else hex(mask)
kern = next((k[7:] for k in sec if k.startswith('kernel ')), 'unknown')
cache = '%s/classmap-%s.tsv' % (sys.argv[2], kern)
kcls = {}
try:
    for l in open(cache):
        k, n = l.split(); kcls[int(k)] = n
except FileNotFoundError: pass
for k, v in kmap.items():
    if v in cls: kcls[k] = cls[v][0]
with open(cache, 'w') as f:
    for k in sorted(kcls): f.write('%d\t%s\n' % (k, kcls[k]))
byname = {v[0]: v for v in cls.values()}
uniq = collections.Counter(); raw = []
for l in sec['avc']:
    m = head.match(l)
    if not m: continue
    comm, pid, ts = m.group(1).strip(), m.group(2), m.group(3)
    d = fields(l)
    ss, ts_, tc = int(d['ssid']), int(d['tsid']), int(d['tclass'])
    den = int(d['denied'], 16); res = int(d['result'])
    sctx = sid.get(ss) or ctx.get(pid) or 'sid=%d' % ss
    tctx = sid.get(ts_) or 'sid=%d' % ts_
    cname = kcls.get(tc, 'kclass%d' % tc)
    ty = int(d.get('ty', 0)); obj = ''
    if ty == 9: obj = 'ino=' + d.get('ino', '?')
    elif ty in (1, 10, 12):
        n = words(d, [{1:'p',10:'d',12:'f'}[ty] + k for k in 'abcd'])
        obj = 'name="%s"' % n if n else ''
    perm = permnames(cname, den)
    mode = 'permissive=%d' % (res == 0)
    raw.append('[%s] avc: denied { %s } for pid=%s comm="%s" %s scontext=%s tcontext=%s tclass=%s %s'
               % (ts, perm, pid, comm, obj, sctx, tctx, cname, mode))
    uniq[(perm, sctx, tctx, cname, mode)] += 1
print('# SID self-test:', 'ok' if ok else 'FAILED (x21 layout differs on this kernel; contexts are unresolved)')
print('# %d denials, %d unique, %d SIDs resolved, %d kernel classes mapped (%s)'
      % (len(raw), len(uniq), len(sid), len(kcls), cache))
print('\n## unique (count, perms, scontext, tcontext, class)')
for (p, s, t, c, md), n in uniq.most_common():
    print('%5d { %s } %s -> %s : %s %s' % (n, p, s, t, c, md))
print('\n## all')
print('\n'.join(raw))
PY
    rm -f "$F.raw"; head -30 "$F.txt"; echo "... full report: $F.txt" ;;
stop)
dev <<'DEVICE'
T=/sys/kernel/tracing
for i in pipa_avc pipa_sid; do [ -d $T/instances/$i ] && { echo 0 > $T/instances/$i/events/enable; rmdir $T/instances/$i; }; done
for e in avc sidq sidm cav ccav; do echo 0 > $T/events/kprobes/$e/enable 2>/dev/null; echo "-:$e" >> $T/kprobe_events 2>/dev/null; done
echo removed
DEVICE
    ;;
*) sed -n '2,7p' "$0"; exit 1 ;;
esac
