package pipa.touch;

import android.os.*;
import java.io.File;
import java.util.*;
import java.util.concurrent.*;
import java.util.regex.*;

/** Original wire implementation. No donor classes or code are shipped. */
public final class TouchService extends Binder {
    public static final String DESCRIPTOR = "vendor.oplus.hardware.touch.IOplusTouch";
    public static final String NAME = DESCRIPTOR + "/default";
    private static final String HASH = "ef41c5fab372bb5ad6a417f606845c87cf0e9b17";
    private final Map<Integer, String> last = new HashMap<>();
    private final Set<IBinder> callbacks = new HashSet<>();
    // Bounded queue. Binder only validates and queues. Return 0 means accepted, not applied.
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 0,
        TimeUnit.SECONDS, new ArrayBlockingQueue<Runnable>(64));
    private final String tool;
    private int edge, corner, ime;
    private static final Pattern IME = Pattern.compile("mod para_V2 set_ime_showing:([01])");

    public TouchService(String tool) {
        this.tool = tool;
        attachInterface(null, DESCRIPTOR);
    }
    public int isTouchNodeSupport(int device, int node) {
        if (device != 0) return -1;
        switch (node) {
            // 255 = the V2 smoothness/sensitivity sliders (COSA support query only); 254 (touch rate) stays off
            case 5: case 8: case 24: case 25: case 243: case 245: case 251: case 252: case 255: return 1;
            default: return -1;
        }
    }
    public synchronized String read(int device, int node) {
        return isTouchNodeSupport(device, node) < 0 ? "" : last.getOrDefault(node, "");
    }
    private static int range(String text, int max) {
        int value = Integer.parseInt(text);
        if (value < 0 || value > max) throw new IllegalArgumentException("range");
        return value;
    }
    // COSA V2 sliders send 1..100 (higher = more responsive), 0 = reset (pi research, FeelAdjustV2Repository).
    // Xiaomi modes 2/3/4 are 0..4 with default 2 (nt36532 nvt_init_touchmode_data). Buckets as OPPO's own legacy
    // path (oa.a.b): 1-20 -> 0 ... 81-100 -> 4.
    private static int level(String text) {
        int v = range(text, 100);
        return v == 0 ? 2 : Math.min(4, (v - 1) / 20);
    }
    // edge_area_level 1..100 (0 = off) -> Xiaomi edge filter 1..3
    private static int edgeLevel(String text) {
        int v = range(text, 100);
        return v == 0 ? 0 : Math.min(3, 1 + (v - 1) / 34);
    }
    public synchronized int write(int device, int node, String text) {
        if (isTouchNodeSupport(device, node) < 0 || text == null || text.length() > 512) return -1;
        int mode, value;
        int nextEdge = edge, nextCorner = corner, nextIme = ime;
        try {
            switch (node) {
                // OPPO direction 0 (0/180 deg), 1 (90), 2 (270) -> Xiaomi orientation 0, 1, 3 (2 = 180)
                case 5: mode = 8; value = new int[] {0, 1, 3}[range(text.trim(), 2)]; break;
                // tap sensitivity -> Touch_UP_THRESHOLD; swipe sensitivity -> Touch_Aim_Sensitivity;
                // V2 smoothness (higher = more sensitive) -> Touch_Tolerance reversed (higher = steadier)
                case 243: mode = 2; value = level(text.trim()); break;
                case 25: mode = 4; value = level(text.trim()); break;
                case 24: mode = 3; value = 4 - level(text.trim()); break;
                case 245: mode = 0; value = range(text.trim(), 1); break;
                case 251: nextEdge = edgeLevel(text.trim()); mode = 7;
                    value = Math.max(nextEdge, Math.max(corner, ime)); break;
                case 252: nextCorner = range(text.trim(), 3); mode = 7;
                    value = Math.max(edge, Math.max(nextCorner, ime)); break;
                case 8:
                    Matcher match = IME.matcher(text.trim());
                    // Unknown grip commands have no safe equivalent. Ignore without claiming success.
                    if (!match.matches()) return -1;
                    nextIme = Integer.parseInt(match.group(1)); mode = 7;
                    value = Math.max(edge, Math.max(corner, nextIme)); break;
                default: return -1;
            }
            final int m = mode, v = value;
            worker.execute(() -> apply(m, v));
            edge = nextEdge; corner = nextCorner; ime = nextIme;
            last.put(node, text);
            return 0;
        } catch (IllegalArgumentException | RejectedExecutionException e) { return -1; }
    }
    private void apply(int mode, int value) {
        java.lang.Process process = null;
        try {
            process = new ProcessBuilder(tool, "set", Integer.toString(mode), Integer.toString(value))
                .redirectInput(new File("/dev/null")).redirectOutput(new File("/dev/null"))
                .redirectError(new File("/dev/null")).start();
            if (!process.waitFor(2, TimeUnit.SECONDS)) {
                process.destroyForcibly();
                System.err.println("touch ioctl timeout mode=" + mode);
            } else if (process.exitValue() != 0) {
                System.err.println("touch ioctl failed mode=" + mode + " exit=" + process.exitValue());
            }
        } catch (Exception e) {
            System.err.println("touch ioctl: " + e);
            if (process != null) process.destroyForcibly();
        }
    }
    private synchronized int callback(IBinder binder, boolean add) {
        if (binder == null) return -1;
        if (add) {
            if (callbacks.contains(binder)) return 0;
            if (callbacks.size() >= 32) return -1;
            callbacks.add(binder);
        } else callbacks.remove(binder);
        return 0; // No event source. Never invoke a callback.
    }
    // OplusTouchInfo is a nullable, size-prefixed stable AIDL parcelable.
    // Transaction 7 is unsupported. Validate its envelope and skip its fields.
    private static void skipInfo(Parcel p) {
        if (p.readInt() == 0) return;
        int start = p.dataPosition(), size = p.readInt();
        if (size < 4 || start > Integer.MAX_VALUE - size || start + size > p.dataSize())
            throw new BadParcelableException("Invalid OplusTouchInfo size");
        p.setDataPosition(start + size);
    }
    @Override public boolean onTransact(int code, Parcel in, Parcel out, int flags) throws RemoteException {
        if (code == INTERFACE_TRANSACTION) { out.writeString(DESCRIPTOR); return true; }
        if (code >= 1 && code <= 16777215) in.enforceInterface(DESCRIPTOR);
        if (code == 16777214 || code == 16777215) {
            out.writeNoException();
            if (code == 16777214) out.writeString(HASH); else out.writeInt(2);
            return true;
        }
        int result;
        switch (code) {
            case 1: in.enforceNoDataAvail(); result = 0; break;
            case 2: {
                int device = in.readInt(), node = in.readInt(); in.enforceNoDataAvail();
                result = isTouchNodeSupport(device, node); break;
            }
            case 3: {
                int device = in.readInt(), node = in.readInt(); in.enforceNoDataAvail();
                out.writeNoException(); out.writeString(read(device, node)); return true;
            }
            case 4: case 5: case 6: {
                int device = in.readInt(), node = in.readInt(); String text = in.readString();
                in.enforceNoDataAvail();
                result = code == 5 ? -1 : write(device, node, text);
                if (code == 6) return true; // oneway: no reply parcel
                break;
            }
            case 7: in.readInt(); skipInfo(in); in.enforceNoDataAvail(); result = -1; break;
            case 8: case 9: {
                IBinder binder = in.readStrongBinder(); in.enforceNoDataAvail();
                result = callback(binder, code == 8); break;
            }
            default: return super.onTransact(code, in, out, flags);
        }
        out.writeNoException(); out.writeInt(result); return true;
    }
}
