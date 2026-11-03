package pipa.hal;

import android.os.*;

/**
 * Base of the pipa HAL shims: one AIDL interface on the stable wire protocol (interface token, codes from
 * FIRST_CALL_TRANSACTION, getInterfaceVersion 16777215, getInterfaceHash 16777214). Own code, no donor classes.
 */
abstract class AidlService extends Binder {
    static final int META_HASH = 16777214, META_VERSION = 16777215;
    final String descriptor, hash;
    final int version;

    AidlService(String descriptor, int version, String hash) {
        this.descriptor = descriptor;
        this.version = version;
        this.hash = hash;
        attachInterface(null, descriptor);
    }

    String name() { return descriptor + "/default"; }

    /** Handle one user transaction. Return false for an unknown code. For a oneway call, do not write a reply. */
    abstract boolean call(int code, Parcel in, Parcel out, boolean oneway) throws RemoteException;

    @Override protected boolean onTransact(int code, Parcel in, Parcel out, int flags) throws RemoteException {
        if (code == INTERFACE_TRANSACTION) { out.writeString(descriptor); return true; }
        if (code == META_HASH || code == META_VERSION) {
            in.enforceInterface(descriptor);
            out.writeNoException();
            if (code == META_HASH) out.writeString(hash); else out.writeInt(version);
            return true;
        }
        if (code < FIRST_CALL_TRANSACTION || code > LAST_CALL_TRANSACTION)
            return super.onTransact(code, in, out, flags);
        in.enforceInterface(descriptor);
        boolean oneway = (flags & FLAG_ONEWAY) != 0;
        try {
            return call(code, in, out, oneway);
        } catch (IllegalArgumentException | IllegalStateException | BadParcelableException e) {
            Log.w(descriptor, "code " + code + ": " + e);
            if (!oneway) { out.setDataPosition(0); out.setDataSize(0); out.writeException(e); }
            return true;
        }
    }

    /** Rate-limited log: at most one line per key every 60 s, so a client in a loop cannot flood logcat. */
    static final class Log {
        private static final java.util.Map<String, Long> last = new java.util.HashMap<>();
        static synchronized void w(String key, String msg) {
            long now = SystemClock.elapsedRealtime();
            Long t = last.get(key);
            if (t != null && now - t < 60000) return;
            last.put(key, now);
            android.util.Log.w("pipa.hal", key + ": " + msg);
        }
    }
}
