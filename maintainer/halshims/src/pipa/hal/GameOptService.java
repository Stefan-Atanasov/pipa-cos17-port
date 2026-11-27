package pipa.hal;

import android.os.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.*;
import org.json.*;

/**
 * vendor.oplus.hardware.gameopt.IGameOptHalService/default, AIDL V2 (notes/cloud/GAMEOPT.md, GAMEOPT-SHIM.md).
 * The donor HAL feeds OPPO's GPA engine; most of its sinks (/proc/game_opt, hmbird, walt tunables, uclamp) are not on
 * pipa. The port kernel has OPPO sched_assist, so the shim does the part that works on pipa, as the donor does:
 * it gives the game's key threads UX priority through /proc/oplus_scheduler/sched_assist/ux_task
 * ("p <tid> 129" = SET|LIGHT, "p <tid> 130" = SET|HEAVY; "p <tid> <bit>" clears only that bit).
 *  - sources: setKeyThread JSON (oiface/COSA: pid, key_thread_ux, white_list names), notifyGameInfo 109
 *    ("<pid>_<tid>", GL thread) and 144 (JSON name -> tid); foreground/background from notifyGameInfo 100 pkgStatus.
 *  - limits: 8 threads per game, 2 games; only LIGHT or HEAVY; a bit that was set before is never touched.
 *  - reset (the donor leaves bits set; the shim does not): background, a new game, process death (10 s check while
 *    a lease exists), 30 min without renewal, shim stop; a lease file lets a restarted shim undo a crash.
 *  - all other calls (per-frame SurfaceFlinger notifications, GPA inputs) return at once without allocation.
 *  - callbacks are kept (so clients see a normal HAL) but never called: their producers do not run on pipa.
 *  - BUGS 175: the donor's GameoptIoctl::bindMainThread (TaskManager bind_main): the game's main thread gets the prime
 *    cluster as preferred cluster (frame boost ioctl 0xc028df01, tool fbgctl). The kernel (fbg_cluster_boost) then
 *    wakes it on cpu7 when cpu7 is idle, else as before. Main thread = engine game thread by name (UEGameThread,
 *    GameThread, UnityMain; the cloud bind_main list is not on pipa). One process only (the kernel honours the last
 *    one); reset with the lease (cluster -1); the lease file line has bit BIND.
 */
final class GameOptService extends AidlService {
    private static final String UX_TASK = "/proc/oplus_scheduler/sched_assist/ux_task";
    private static final String LEASES = "/data/misc/pipa_port/gameopt_leases";
    private static final int LIGHT = 1, HEAVY = 2, SET = 0x80;
    private static final int MAX_GAMES = 2, MAX_THREADS = 8, MAX_CALLBACKS = 8;
    private static final int MAX_PENDING = 64, MAX_STRING = 64 * 1024, MIN_APP_UID = 10000;
    private static final Pattern UX_STATE = Pattern.compile("ux_state=0x([0-9a-fA-F]+)");
    private static final long LEASE_MS = 30 * 60 * 1000L, CHECK_MS = 10 * 1000L;
    private static final String FBGCTL = "/system_ext/pipa_port/fbgctl";
    private static final String[] MAIN_NAMES = { "UEGameThread", "GameThread", "UnityMain" };   // best first
    private static final int BIND = 0x100, PRIME_CLUSTER = 2, MAX_BIND_TRIES = 18;   // 18 lease checks = 3 min

    private static final class Boost {
        final int tid; final long start; final int bit;
        Boost(int tid, long start, int bit) { this.tid = tid; this.start = start; this.bit = bit; }
    }
    private static final class Lease {
        final int pid; final long pidStart; long renewed; final List<Boost> threads = new ArrayList<>();
        int bindTries; boolean bound;
        Lease(int pid, long pidStart) { this.pid = pid; this.pidStart = pidStart; }
    }

    private final Map<Integer, Lease> leases = new LinkedHashMap<>();   // only touched on the handler thread
    private final Handler h;
    private IBinder legacyCallback;
    private final Map<String, IBinder> callbacks = new HashMap<>();
    private final AtomicInteger pending = new AtomicInteger();   // messages posted by binder calls, not yet run
    private boolean checkPending;                                // guarded by leases
    private final Runnable check = () -> guarded("check", this::checkLeases);

    GameOptService() {
        super("vendor.oplus.hardware.gameopt.IGameOptHalService", 2, "79187eecf42abc41850736c8590e8c5e0bea0660");
        HandlerThread t = new HandlerThread("pipa.gameopt");
        t.start();
        h = new Handler(t.getLooper());
        h.post(() -> guarded("replay", this::replayLeaseFile));
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            synchronized (leases) { for (Lease l : new ArrayList<>(leases.values())) reset(l); }
        }));
    }

    // ------------------------------------------------------------------ binder
    @Override boolean call(int code, Parcel in, Parcel out, boolean oneway) {
        switch (code) {
            case 1: { int type = in.readInt(); String info = in.readString();          // notifyGameInfo (oneway)
                if ((type == 100 || type == 109 || type == 144) && ok(info)) post("info " + type, () -> gameInfo(type, info));
                return true; }
            case 2: case 9: case 10: case 11: case 12: case 13: case 14: return true;    // per-frame / GPA: drop
            case 3: in.readInt(); out.writeNoException(); out.writeInt(0); return true;  // notifyTGPAfps
            case 4: { IBinder cb = in.readStrongBinder();                                 // setCallback
                out.writeNoException(); out.writeInt(setLegacy(cb)); return true; }
            case 5: { String json = in.readString(); if (ok(json)) post("key thread", () -> keyThread(json)); return true; }  // setKeyThread
            case 6: { IBinder cb = in.readStrongBinder();                                 // unsetCallback
                synchronized (callbacks) { if (cb != null && cb == legacyCallback) legacyCallback = null; }
                out.writeNoException(); out.writeInt(0); return true; }
            case 7: { String key = in.readString(); IBinder cb = in.readStrongBinder();   // registerCallback
                keep(key, cb); return true; }
            case 8: { String key = in.readString();                                       // unregisterCallback
                synchronized (callbacks) { callbacks.remove(key); } return true; }
            default: return false;
        }
    }

    private static boolean ok(String s) { return s != null && s.length() <= MAX_STRING; }

    /** Post work from a binder thread: bounded queue, and nothing thrown on the handler thread can end the host. */
    private void post(String what, Runnable r) {
        if (pending.incrementAndGet() > MAX_PENDING) { pending.decrementAndGet(); Log.w("gameopt", "queue full: " + what); return; }
        h.post(() -> { pending.decrementAndGet(); guarded(what, r); });
    }
    private static void guarded(String what, Runnable r) {
        try { r.run(); } catch (Throwable t) { Log.w("gameopt", what + ": " + t); }
    }

    private int setLegacy(IBinder cb) {
        if (cb == null) return -1;
        synchronized (callbacks) { legacyCallback = cb; }
        try { cb.linkToDeath(() -> { synchronized (callbacks) { if (legacyCallback == cb) legacyCallback = null; } }, 0); }
        catch (RemoteException e) { synchronized (callbacks) { legacyCallback = null; } }
        return 0;
    }
    private void keep(String key, IBinder cb) {
        if (key == null || cb == null) return;
        synchronized (callbacks) {
            if (!callbacks.containsKey(key) && callbacks.size() >= MAX_CALLBACKS) return;
            callbacks.put(key, cb);
        }
        try { cb.linkToDeath(() -> { synchronized (callbacks) { callbacks.remove(key, cb); } }, 0); }
        catch (RemoteException e) { synchronized (callbacks) { callbacks.remove(key, cb); } }
    }

    // ------------------------------------------------------------------ game state (handler thread)
    private void gameInfo(int type, String info) {
        try {
            if (type == 100) {
                // not real JSON: values are unquoted, e.g. {"package":com.x,"pid":-1,"pkgStatus":1,
                // "secondPackage":com.android.launcher:13059} (seen 2026-11-03): read the two numbers by pattern
                int status = intField(info, "pkgStatus", -1), pid = intField(info, "pid", 0);
                if (status == 1) { if (pid > 0) reset(pid); else resetAll(); }        // background
                else if (status == 3) { resetAll(); if (pid > 0) bindMain(lease(pid, true)); }   // new game to fg
                else if ((status == 11 || status == 12) && pid > 0) bindMain(lease(pid, true));  // fg: renew
            } else if (type == 109) {                                                   // "<pid>_<tid>" GL thread
                String[] p = info.trim().split("_");
                if (p.length == 2) {
                    int pid = Integer.parseInt(p[0]);
                    boost(pid, Integer.parseInt(p[1]), LIGHT);
                    if (leases.containsKey(pid)) bindMain(lease(pid, false));
                }
            } else if (type == 144) {                                                   // {"name": tid, ...}
                JSONObject o = new JSONObject(info);
                for (Iterator<String> it = o.keys(); it.hasNext(); ) {
                    int tid = o.optInt(it.next(), 0);
                    int pid = tgid(tid);
                    if (pid > 0) boost(pid, tid, LIGHT);
                }
            }
        } catch (JSONException | NumberFormatException e) { Log.w("gameopt", "type " + type + ": " + e); }
    }

    private void keyThread(String json) {
        try {
            JSONObject o = new JSONObject(json);
            int pid = parseInt(o.opt("pid"));
            if (pid <= 0) return;
            if ("0".equals(String.valueOf(o.opt("status")))) { reset(pid); return; }
            int ux = parseInt(o.opt("key_thread_ux"));
            int bit = (ux & SET) != 0 && (ux & HEAVY) != 0 ? HEAVY : LIGHT;            // only SET|LIGHT or SET|HEAVY
            Set<String> names = new LinkedHashSet<>();
            for (String k : new String[] { "white_list", "key_thread_value", "key_worker" }) {
                JSONArray a = o.optJSONArray(k);
                if (a != null) for (int i = 0; i < a.length(); i++) names.add(a.optString(i));
            }
            if (names.isEmpty()) return;
            File[] tasks = new File("/proc/" + pid + "/task").listFiles();
            if (tasks == null) return;
            for (File t : tasks) {
                String comm = read(t.getPath() + "/comm");
                if (comm == null) continue;
                for (String n : names)
                    if (!n.isEmpty() && comm.equals(n.length() > 15 ? n.substring(0, 15) : n)) {
                        boost(pid, Integer.parseInt(t.getName()), bit);
                        break;
                    }
            }
        } catch (JSONException | NumberFormatException e) { Log.w("gameopt", "key thread: " + e); }
    }

    /** "name":<int> anywhere in the text (OPPO's type 100 info is not valid JSON) */
    private static int intField(String s, String name, int dflt) {
        Matcher m = Pattern.compile("\"" + name + "\"\\s*:\\s*\"?(-?\\d+)").matcher(s);
        return m.find() ? Integer.parseInt(m.group(1)) : dflt;
    }

    private static int parseInt(Object v) {
        if (v == null) return 0;
        try { return v instanceof Number ? ((Number) v).intValue() : Integer.parseInt(String.valueOf(v).trim()); }
        catch (NumberFormatException e) { return 0; }
    }

    // ------------------------------------------------------------------ leases
    /** The lease of a game; renew only on foreground status (11/12, 3), so the 30 min cap holds. App uids only. */
    private Lease lease(int pid, boolean renew) {
        synchronized (leases) {
            Lease l = leases.get(pid);
            long start = startTime(pid, pid);
            if (l != null && l.pidStart != start) { leases.remove(pid); l = null; }   // pid was reused
            if (l == null) {
                if (start <= 0 || uid(pid) < MIN_APP_UID) return null;
                renew = true;                                    // new lease: the clock starts now
                if (leases.size() >= MAX_GAMES) reset(leases.values().iterator().next());
                l = new Lease(pid, start);
                leases.put(pid, l);
            }
            if (renew) l.renewed = SystemClock.elapsedRealtime();
            if (!checkPending) { checkPending = true; h.postDelayed(check, CHECK_MS); }
            return l;
        }
    }

    private void boost(int pid, int tid, int bit) {
        if (tgid(tid) != pid) return;                       // the thread must belong to the game
        Lease l = lease(pid, false);
        if (l == null) return;
        synchronized (leases) {
            for (Boost b : l.threads) if (b.tid == tid && b.bit != BIND) return;
            if (l.threads.size() >= MAX_THREADS) return;
            long start = startTime(pid, tid);
            int state = uxState(pid, tid);
            if (start <= 0 || state < 0) return;
            if ((state & bit) != 0) return;                 // already set by someone else: not ours
            if (!writeUx(tid, SET | bit)) return;
            l.threads.add(new Boost(tid, start, bit));
            saveLeaseFile();
        }
    }

    /** bindMainThread: preferred cluster = prime for the engine game thread (once per lease, retried by the check). */
    private void bindMain(Lease l) {
        if (l == null) return;
        synchronized (leases) {
            if (l.bound || l.bindTries >= MAX_BIND_TRIES || leases.get(l.pid) != l) return;
            l.bindTries++;
            File[] tasks = new File("/proc/" + l.pid + "/task").listFiles();
            if (tasks == null) return;
            // best name first; for the same name the busiest thread (UE4 starts short helper threads with the
            // same name later: PUBG 2026-11-25 had 4 "UEGameThread", one with all the CPU time)
            int best = MAIN_NAMES.length, tid = 0;
            long busiest = -1;
            for (File t : tasks) {
                String comm = read(t.getPath() + "/comm");
                for (int i = 0; comm != null && i <= best && i < MAIN_NAMES.length; i++)
                    if (comm.equals(MAIN_NAMES[i])) {
                        long cpu = cpuTime(t.getPath() + "/stat");
                        if (i < best || cpu > busiest) {
                            try { tid = Integer.parseInt(t.getName()); best = i; busiest = cpu; }
                            catch (NumberFormatException e) { /* skip */ }
                        }
                        break;
                    }
            }
            if (tid <= 0) return;
            long start = startTime(l.pid, tid);
            if (start <= 0) return;
            for (Lease o : leases.values()) if (o != l && o.bound) unbind(o);   // the kernel honours one process
            if (!fbg(tid, PRIME_CLUSTER)) return;
            l.threads.add(new Boost(tid, start, BIND));
            l.bound = true;
            l.bindTries = MAX_BIND_TRIES;
            saveLeaseFile();
            Log.w("gameopt", "bind main " + l.pid + "/" + tid + " " + MAIN_NAMES[best] + " -> prime");
        }
    }
    private void unbind(Lease l) {
        for (Iterator<Boost> it = l.threads.iterator(); it.hasNext(); ) {
            Boost b = it.next();
            if (b.bit == BIND) { clear(l.pid, b); it.remove(); }
        }
        l.bound = false;
        l.bindTries = MAX_BIND_TRIES;   // the other game keeps the bind
    }

    private void reset(int pid) { synchronized (leases) { Lease l = leases.get(pid); if (l != null) reset(l); } }
    private void resetAll() { synchronized (leases) { for (Lease l : new ArrayList<>(leases.values())) reset(l); } }

    private void reset(Lease l) {
        synchronized (leases) {
            for (Boost b : l.threads) clear(l.pid, b);
            leases.remove(l.pid);
            saveLeaseFile();
        }
    }
    private void clear(int pid, Boost b) {
        if (startTime(pid, b.tid) != b.start) return;      // gone or tid reused: nothing to undo
        if (b.bit == BIND) { fbg(b.tid, -1); return; }
        int state = uxState(pid, b.tid);
        if (state >= 0 && (state & b.bit) != 0) writeUx(b.tid, b.bit);   // no SET bit: clears only our bit
    }

    private void checkLeases() {
        synchronized (leases) {
            checkPending = false;
            long now = SystemClock.elapsedRealtime();
            for (Lease l : new ArrayList<>(leases.values())) {
                if (startTime(l.pid, l.pid) != l.pidStart) { leases.remove(l.pid); saveLeaseFile(); }  // died
                else if (now - l.renewed > LEASE_MS) reset(l);
                else bindMain(l);                                  // no-op once bound or after MAX_BIND_TRIES
            }
            if (!leases.isEmpty()) { checkPending = true; h.postDelayed(check, CHECK_MS); }
        }
    }

    // lease file: one line per boosted thread "pid tid start bit"; replayed (cleared) at shim start
    private void saveLeaseFile() {
        StringBuilder sb = new StringBuilder();
        for (Lease l : leases.values())
            for (Boost b : l.threads) sb.append(l.pid).append(' ').append(b.tid).append(' ').append(b.start)
                .append(' ').append(b.bit).append('\n');
        File tmp = new File(LEASES + ".tmp");
        try (FileOutputStream o = new FileOutputStream(tmp)) {
            o.write(sb.toString().getBytes());
        } catch (IOException e) { return; }
        if (!tmp.renameTo(new File(LEASES))) tmp.delete();
    }
    private void replayLeaseFile() {
        try (BufferedReader r = new BufferedReader(new FileReader(LEASES))) {
            String line;
            while ((line = r.readLine()) != null) {
                String[] f = line.trim().split(" ");
                if (f.length == 4)
                    clear(Integer.parseInt(f[0]), new Boost(Integer.parseInt(f[1]), Long.parseLong(f[2]),
                        Integer.parseInt(f[3])));
            }
        } catch (IOException | NumberFormatException e) { /* no file: nothing to undo */ }
        new File(LEASES).delete();
    }

    // ------------------------------------------------------------------ /proc
    static String read(String path) {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String s = r.readLine();
            return s == null ? null : s.trim();
        } catch (IOException | SecurityException e) { return null; }
    }
    private static int tgid(int tid) {
        String s = null;
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/" + tid + "/status"))) {
            String line;
            while ((line = r.readLine()) != null) if (line.startsWith("Tgid:")) { s = line.substring(5).trim(); break; }
        } catch (IOException | SecurityException e) { return -1; }
        try { return s == null ? -1 : Integer.parseInt(s); } catch (NumberFormatException e) { return -1; }
    }
    /** real uid of a process from /proc/<pid>/status ("Uid:\t<real>\t<eff>..."), -1 if unknown */
    private static int uid(int pid) {
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/" + pid + "/status"))) {
            String line;
            while ((line = r.readLine()) != null)
                if (line.startsWith("Uid:")) return Integer.parseInt(line.substring(4).trim().split("\\s+")[0]);
        } catch (IOException | SecurityException | NumberFormatException e) { /* gone */ }
        return -1;
    }
    /** field 22 (starttime) of /proc/<pid>/task/<tid>/stat; -1 if the thread is gone */
    private static long startTime(int pid, int tid) {
        String s = read("/proc/" + pid + "/task/" + tid + "/stat");
        if (s == null) return -1;
        int p = s.lastIndexOf(')');
        String[] f = s.substring(p + 2).split(" ");
        try { return f.length > 19 ? Long.parseLong(f[19]) : -1; } catch (NumberFormatException e) { return -1; }
    }
    /** utime + stime (fields 14, 15) of a stat file; -1 if unreadable */
    private static long cpuTime(String statPath) {
        String s = read(statPath);
        if (s == null) return -1;
        String[] f = s.substring(s.lastIndexOf(')') + 2).split(" ");
        try { return f.length > 12 ? Long.parseLong(f[11]) + Long.parseLong(f[12]) : -1; }
        catch (NumberFormatException e) { return -1; }
    }
    private static int uxState(int pid, int tid) {
        String s = read("/proc/" + pid + "/task/" + tid + "/ux_state");   // "pid=.. ux_state=0x00000000 inherit=0(..) .."
        if (s == null) return -1;
        Matcher m = UX_STATE.matcher(s);
        if (!m.find()) return -1;
        try { return (int) Long.parseLong(m.group(1), 16); } catch (NumberFormatException e) { return -1; }
    }
    /** fbgctl cluster <tid> <cluster> (ioctl on /proc/oplus_frame_boost/sys_ctrl); false on any error */
    private static boolean fbg(int tid, int cluster) {
        java.lang.Process pr = null;
        try {
            pr = new ProcessBuilder(FBGCTL, "cluster", Integer.toString(tid), Integer.toString(cluster))
                .redirectInput(new File("/dev/null")).redirectOutput(new File("/dev/null"))
                .redirectError(new File("/dev/null")).start();
            if (!pr.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)) { pr.destroyForcibly(); return false; }
            if (pr.exitValue() == 0) return true;
            Log.w("gameopt", "fbgctl exit " + pr.exitValue());
        } catch (IOException | InterruptedException e) {
            Log.w("gameopt", "fbgctl: " + e);
            if (pr != null) pr.destroyForcibly();
        }
        return false;
    }
    private static boolean writeUx(int tid, int value) {
        try (FileOutputStream o = new FileOutputStream(UX_TASK)) {
            o.write(("p " + tid + " " + value).getBytes());
            return true;
        } catch (IOException | SecurityException e) {
            Log.w("gameopt", "ux_task: " + e);
            return false;
        }
    }
}
