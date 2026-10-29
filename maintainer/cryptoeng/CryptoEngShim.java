// Software stand-in for OPPO's vendor.oplus.hardware.cryptoeng.ICryptoeng/default (BUGS-TODO B8). ColorOS keeps the
// privacy password (Settings > Privacy, app lock and hidden apps in SafeCenter) in a TEE app that pipa cannot load.
// This service speaks the same command protocol and keeps the records in a root-only directory on /data.
//
//   app_process -Djava.class.path=/system_ext/pipa_port/cryptoeng.jar /system/bin CryptoEngShim [dir]
//
// Protocol (Settings com.oplus.settings.privacy.sdk.MethodBuffer / RpmbResultParser, big-endian u32):
//   request  = cmd, 10000, nparams, { type, len, payload }...
//   response = cmd, status (0 = ok, 10014 invalid, 10017 wrong secret), nparams, { type, len, payload }...
// Commands: 4001 enroll, 4002 verify (1 password, 2 security answer), 4003 modify (1 password, 2 answer, 4 email),
// 4004 delete, 4005 get info. Online recovery (verify 3/4/8, 4006) needs OPPO's servers and keys: refused.
// Every other command (OPPO's TEE crypto SDK in many apps: 10001-10020 PKI, RPMB 2014, 13001-13005) and every
// refused caller gets a null array, which CryptoEngManager returns as is: the same result as before this service
// existed, so those apps keep their "no TEE" path (an error status made pkiCertVerify return false instead).
// The client sends SHA256(SHA256(password) || handler); the record keeps that value (the TEE does the same). Like the
// TEE, the handler changes with each new password. 5 wrong entries lock for 30 s, then 60 s, ... up to 1 h.
// Only uid 1000 (Settings, SafeCenter) and root may call. Not TEE-grade: root can read or reset the records.
import android.os.Binder;
import android.os.IBinder;
import android.os.Looper;
import android.os.Parcel;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Properties;
import java.util.Set;

public final class CryptoEngShim extends Binder {
    static final String TAG = "PipaCryptoEng";
    static final String NAME = "vendor.oplus.hardware.cryptoeng.ICryptoeng/default";
    static final String DESCRIPTOR = "vendor.oplus.hardware.cryptoeng.ICryptoeng";
    static final String HASH = "765136eb397eb5b85ee1e089d8fec72c15e266b3";   // ICryptoeng V1
    static final int TX_INVOKE = 1, TX_HASH = 16777214, TX_VERSION = 16777215;

    static final int ENROLL = 4001, VERIFY = 4002, MODIFY = 4003, DELETE = 4004, GET_INFO = 4005;
    static final int OK = 0, INVALID = 10014, MISMATCH = 10017;
    static final int P_NS = 201, P_PWD = 202, P_SECURE = 203, P_VTYPE = 204, P_VBUF = 205, P_CHALLENGE = 206,
            P_ITYPE = 207, P_IBUF = 208, P_HANDLER = 209, P_PTYPE = 210, P_RETRY = 211, P_LOCK = 212,
            P_EMAIL = 217, P_QRETRY = 219, P_QLOCK = 220;
    static final int MAX_TRIES = 5;
    static final long CHALLENGE_MS = 10 * 60 * 1000;

    final File dir;
    final SecureRandom random = new SecureRandom();
    final Map<Integer, byte[]> challenges = new HashMap<>();
    final Map<Integer, Long> challengeEnd = new HashMap<>();
    final Set<Integer> refused = new HashSet<>();   // log each refused uid once (FindMyPhone asks in bursts)
    final Set<Integer> foreign = new HashSet<>();   // and each command that is not ours

    CryptoEngShim(File dir) {
        this.dir = dir;
        attachInterface(null, DESCRIPTOR);
    }

    public static void main(String[] args) throws Exception {
        File dir = new File(args.length > 0 ? args[0] : "/data/misc/pipa_port/cryptoeng");
        dir.mkdirs();
        dir.setReadable(false, false); dir.setWritable(false, false); dir.setExecutable(false, false);
        dir.setReadable(true, true); dir.setWritable(true, true); dir.setExecutable(true, true);
        Looper.prepareMainLooper();
        CryptoEngShim shim = new CryptoEngShim(dir);
        // ServiceManager is hidden API; app_process has no hidden-API enforcement.
        Class.forName("android.os.ServiceManager").getMethod("addService", String.class, IBinder.class)
                .invoke(null, NAME, shim);
        Log.i(TAG, "registered " + NAME + ", records in " + dir);
        Looper.loop();
    }

    @Override
    protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws android.os.RemoteException {
        switch (code) {
            case TX_INVOKE: {
                data.enforceInterface(DESCRIPTOR);
                byte[] in = data.createByteArray();
                int uid = Binder.getCallingUid();
                byte[] out;
                if (uid != 1000 && uid != 0) {
                    if (refused.add(uid)) Log.w(TAG, "refused caller uid " + uid + " (logged once)");
                    out = null;
                } else {
                    out = invoke(in, uid);
                }
                reply.writeNoException();
                reply.writeByteArray(out);
                return true;
            }
            case TX_HASH:
                data.enforceInterface(DESCRIPTOR);
                reply.writeNoException();
                reply.writeString(HASH);
                return true;
            case TX_VERSION:
                data.enforceInterface(DESCRIPTOR);
                reply.writeNoException();
                reply.writeInt(1);
                return true;
            default:
                return super.onTransact(code, data, reply, flags);
        }
    }

    // ---------------------------------------------------------------- protocol

    synchronized byte[] invoke(byte[] in, int uid) {
        if (in == null || in.length < 12) return null;
        ByteBuffer b = ByteBuffer.wrap(in);
        int cmd = b.getInt(), magic = b.getInt(), n = b.getInt();
        if (cmd < ENROLL || cmd > GET_INFO) {
            if (foreign.add(cmd)) Log.i(TAG, "uid " + uid + ": command " + cmd + " is not a privacy-password command, no answer (logged once)");
            return null;
        }
        Map<Integer, byte[]> p = new HashMap<>();
        for (int i = 0; i < n; i++) {
            if (b.remaining() < 8) return response(cmd, INVALID, null);
            int type = b.getInt(), len = b.getInt();
            if (len < 0 || len > b.remaining()) return response(cmd, INVALID, null);
            byte[] v = new byte[len];
            b.get(v);
            p.put(type, v);
        }
        int ns = intOf(p, P_NS, 1);
        try {
            switch (cmd) {
                case ENROLL: return enroll(ns, p);
                case VERIFY: return verify(ns, p);
                case MODIFY: return modify(ns, p);
                case DELETE: return delete(ns, p);
                case GET_INFO: return info(ns, p);
                default:
                    Log.w(TAG, "uid " + uid + ": unsupported command " + cmd + " (magic " + magic + ")");
                    return null;
            }
        } catch (Exception e) {
            Log.e(TAG, "command " + cmd + " failed", e);
            return response(cmd, INVALID, null);
        }
    }

    byte[] enroll(int ns, Map<Integer, byte[]> p) throws Exception {
        int type = intOf(p, P_PTYPE, 0);
        byte[] pwd = p.get(P_PWD);
        if (type < 1 || type > 5 || pwd == null || pwd.length != 32) return response(ENROLL, INVALID, null);
        Properties r = new Properties();
        byte[] handler = randomBytes(8);
        put(r, "type", type);
        put(r, "handler", handler);
        put(r, "verifier", sha256(pwd, handler));
        // 203: records { u32 type, u32 len, 32-byte area }: 2 = SHA256(answer), 4 and 10 = email (first 32, rest)
        byte[] sec = p.get(P_SECURE);
        if (sec != null) {
            ByteBuffer b = ByteBuffer.wrap(sec);
            ByteArrayOutputStream email = new ByteArrayOutputStream();
            while (b.remaining() >= 8) {
                int t = b.getInt(), len = b.getInt();
                byte[] area = new byte[Math.min(32, b.remaining())];
                b.get(area);
                if (len < 0 || len > area.length) return response(ENROLL, INVALID, null);
                if (t == 2 && len == 32) put(r, "answer", area);
                else if (t == 4 || t == 10) email.write(area, 0, len);
            }
            if (email.size() > 0) put(r, "email", email.toByteArray());
        }
        save(ns, r);
        dropChallenge(ns);
        Log.i(TAG, "ns " + ns + ": enrolled, type " + type);
        return response(ENROLL, OK, params().i(P_HANDLER, handler));
    }

    byte[] verify(int ns, Map<Integer, byte[]> p) throws Exception {
        int sel = intOf(p, P_VTYPE, 0);
        byte[] v = p.get(P_VBUF);
        Properties r = load(ns);
        String key = sel == 1 ? "verifier" : sel == 2 ? "answer" : null;
        if (key == null) {
            Log.w(TAG, "ns " + ns + ": verify type " + sel + " (online recovery) is not supported");
            return response(VERIFY, INVALID, null);
        }
        String fails = sel == 1 ? "fails" : "qfails", until = sel == 1 ? "lock" : "qlock";
        byte[] want = r == null ? null : bytes(r, key);
        if (want == null || v == null) return response(VERIFY, MISMATCH, null);
        if (lockLeft(r, until) > 0) return response(VERIFY, MISMATCH, null);
        if (!MessageDigest.isEqual(want, v)) {
            int f = num(r, fails) + 1;
            put(r, fails, f);
            if (f % MAX_TRIES == 0) {
                long s = Math.min(3600, 30L << Math.min(7, f / MAX_TRIES - 1));
                put(r, until, System.currentTimeMillis() + s * 1000);
                Log.i(TAG, "ns " + ns + ": " + f + " wrong entries, locked " + s + " s");
            }
            save(ns, r);
            return response(VERIFY, MISMATCH, null);
        }
        if (num(r, fails) != 0) { put(r, fails, 0); put(r, until, 0); save(ns, r); }
        Log.d(TAG, "ns " + ns + ": verify " + sel + " ok");
        byte[] c = randomBytes(64);
        challenges.put(ns, c);
        challengeEnd.put(ns, System.currentTimeMillis() + CHALLENGE_MS);
        return response(VERIFY, OK, params().i(P_CHALLENGE, c));
    }

    byte[] modify(int ns, Map<Integer, byte[]> p) throws Exception {
        Properties r = load(ns);
        if (r == null || !challengeOk(ns, p.get(P_CHALLENGE))) return response(MODIFY, INVALID, null);
        int sel = intOf(p, P_ITYPE, 0);
        byte[] v = p.get(P_IBUF);
        if (v == null || v.length == 0) return response(MODIFY, INVALID, null);
        switch (sel) {
            case 1: {
                int type = intOf(p, P_PTYPE, num(r, "type"));
                if (v.length != 32 || type < 1 || type > 5) return response(MODIFY, INVALID, null);
                byte[] handler = randomBytes(8);
                put(r, "type", type);
                put(r, "handler", handler);
                put(r, "verifier", sha256(v, handler));
                put(r, "fails", 0); put(r, "lock", 0);
                save(ns, r);
                Log.i(TAG, "ns " + ns + ": password changed, type " + type);
                return response(MODIFY, OK, params().i(P_HANDLER, handler));
            }
            case 2:
                if (v.length != 32) return response(MODIFY, INVALID, null);
                put(r, "answer", v); put(r, "qfails", 0); put(r, "qlock", 0);
                save(ns, r);
                Log.i(TAG, "ns " + ns + ": security answer changed");
                return response(MODIFY, OK, null);
            case 4:
                put(r, "email", v);
                save(ns, r);
                return response(MODIFY, OK, null);
            default:
                return response(MODIFY, INVALID, null);
        }
    }

    byte[] delete(int ns, Map<Integer, byte[]> p) {
        if (load(ns) == null || !challengeOk(ns, p.get(P_CHALLENGE))) return response(DELETE, INVALID, null);
        file(ns).delete();
        dropChallenge(ns);
        Log.i(TAG, "ns " + ns + ": deleted");
        return response(DELETE, OK, null);
    }

    byte[] info(int ns, Map<Integer, byte[]> p) throws Exception {
        Properties r = load(ns);
        if (r == null) return response(GET_INFO, OK, params().i(P_PTYPE, 0));
        Params out = params().i(P_PTYPE, num(r, "type")).i(P_HANDLER, bytes(r, "handler"))
                .i(P_RETRY, MAX_TRIES - num(r, "fails") % MAX_TRIES).i(P_LOCK, lockLeft(r, "lock"))
                .i(P_QRETRY, MAX_TRIES - num(r, "qfails") % MAX_TRIES).i(P_QLOCK, lockLeft(r, "qlock"));
        byte[] email = bytes(r, "email");
        if (email != null && email.length > 0)
            out.i(P_EMAIL, intOf(p, P_EMAIL, 0) == 1 ? mask(new String(email, "UTF-8")).getBytes("UTF-8") : email);
        return response(GET_INFO, OK, out);
    }

    boolean challengeOk(int ns, byte[] c) {
        byte[] want = challenges.get(ns);
        Long end = challengeEnd.get(ns);
        return c != null && want != null && end != null && System.currentTimeMillis() < end
                && MessageDigest.isEqual(want, c);
    }

    void dropChallenge(int ns) {
        challenges.remove(ns);
        challengeEnd.remove(ns);
    }

    static String mask(String email) {
        int at = email.indexOf('@');
        if (at <= 0) return "***";
        String user = email.substring(0, at);
        return user.substring(0, Math.min(2, user.length())) + "***" + email.substring(at);
    }

    // ---------------------------------------------------------------- encoding

    static final class Params {
        final ByteArrayOutputStream buf = new ByteArrayOutputStream();
        int count;
        Params i(int type, int value) { return i(type, ByteBuffer.allocate(4).putInt(value).array()); }
        Params i(int type, byte[] value) {
            if (value == null || value.length == 0) return this;   // the client parser cannot skip empty params
            buf.write(ByteBuffer.allocate(8).putInt(type).putInt(value.length).array(), 0, 8);
            buf.write(value, 0, value.length);
            count++;
            return this;
        }
    }

    static Params params() { return new Params(); }

    static byte[] response(int cmd, int status, Params p) {
        byte[] body = p == null ? new byte[0] : p.buf.toByteArray();
        return ByteBuffer.allocate(12 + body.length).putInt(cmd).putInt(status).putInt(p == null ? 0 : p.count)
                .put(body).array();
    }

    static int intOf(Map<Integer, byte[]> p, int type, int dflt) {
        byte[] v = p.get(type);
        return v != null && v.length == 4 ? ByteBuffer.wrap(v).getInt() : dflt;
    }

    byte[] randomBytes(int n) {
        byte[] b = new byte[n];
        random.nextBytes(b);
        return b;
    }

    static byte[] sha256(byte[] a, byte[] b) throws Exception {
        MessageDigest d = MessageDigest.getInstance("SHA-256");
        d.update(a);
        d.update(b);
        return d.digest();
    }

    // ---------------------------------------------------------------- storage (one properties file per namespace)

    File file(int ns) { return new File(dir, "ns" + ns + ".prop"); }

    Properties load(int ns) {
        File f = file(ns);
        if (!f.exists()) return null;
        Properties r = new Properties();
        try (FileInputStream in = new FileInputStream(f)) {
            r.load(in);
        } catch (Exception e) {
            Log.e(TAG, "cannot read " + f, e);
            return null;
        }
        return r;
    }

    void save(int ns, Properties r) throws Exception {
        File f = file(ns), tmp = new File(dir, f.getName() + ".tmp");
        try (FileOutputStream out = new FileOutputStream(tmp)) {
            r.store(out, null);
            out.getFD().sync();
        }
        tmp.setReadable(false, false);
        tmp.setReadable(true, true);
        if (!tmp.renameTo(f)) throw new Exception("rename failed: " + tmp);
    }

    static void put(Properties r, String k, long v) { r.setProperty(k, Long.toString(v)); }

    static void put(Properties r, String k, byte[] v) {
        StringBuilder s = new StringBuilder();
        for (byte x : v) s.append(String.format("%02x", x & 0xff));
        r.setProperty(k, s.toString());
    }

    static int num(Properties r, String k) {
        try { return (int) Long.parseLong(r.getProperty(k, "0")); } catch (NumberFormatException e) { return 0; }
    }

    static int lockLeft(Properties r, String k) {
        long until;
        try { until = Long.parseLong(r.getProperty(k, "0")); } catch (NumberFormatException e) { return 0; }
        long left = until - System.currentTimeMillis();
        return left > 0 ? (int) ((left + 999) / 1000) : 0;
    }

    static byte[] bytes(Properties r, String k) {
        String s = r.getProperty(k);
        if (s == null || s.length() % 2 != 0) return null;
        byte[] b = new byte[s.length() / 2];
        for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(s.substring(2 * i, 2 * i + 2), 16);
        return b;
    }
}
