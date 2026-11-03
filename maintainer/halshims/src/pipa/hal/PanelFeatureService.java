package pipa.hal;

import android.os.*;
import java.io.*;
import java.util.*;

/**
 * vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default, AIDL V1 (notes/cloud/DISPLAY-HALS.md
 * part A). pipa has no OPPO panel driver (/sys/kernel/oplus_display). This shim answers like the donor service:
 *  - real values where pipa has them: 8/30 max brightness and 29 brightness (panel0-backlight);
 *  - info 9 (panel make, used by the OPPO ALS code to pick its coefficients) only from an OPPO-format
 *    /proc/devinfo/lcd; a Xiaomi panel string could select wrong values, so without it the answer stays -1;
 *  - probe ids answer "not supported" (0), so no OPPO-only panel feature (FOD dim layer, PWM pulse, ADFR, ...)
 *    turns on;
 *  - set ids that the callers expect to work (CABC, dynamic TE, ...) are accepted and kept for get; they change
 *    nothing on the pipa panel;
 *  - every other id: status -1, as the donor service for an id without a handler ("default, no choice!").
 * Ids >= 0x1000 address a second panel (OPPO foldables); pipa has one panel: -1.
 */
final class PanelFeatureService extends AidlService {
    private static final String BL = "/sys/class/backlight/panel0-backlight/";
    // get ids that answer 0 = "not supported" / default (A.5.2 "constant answer")
    private static final Set<Integer> PROBE = set(5, 6, 13, 14, 20, 34, 69, 179, 183, 211, 212, 233, 247, 264);
    // set ids that callers send in normal use; accept, keep the value for get (A.5.2 "accept and ignore")
    private static final Set<Integer> KEEP = set(4, 7, 18, 22, 28, 68, 184, 185, 186, 192, 194, 195, 199, 201, 210,
        213, 217, 234, 235, 245, 246, 260, 265, 267);
    private static final String DEVINFO_LCD = "/proc/devinfo/lcd";   // OPPO kernel format only [device check]
    private final Map<Integer, int[]> kept = new HashMap<>();

    PanelFeatureService() {
        super("vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature", 1,
              "39afca22ac77253421ad681eeb2bae0c6ff62c13");
    }

    private static Set<Integer> set(int... v) {
        Set<Integer> s = new HashSet<>();
        for (int i : v) s.add(i);
        return Collections.unmodifiableSet(s);
    }

    static String readLine(String path) {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String s = r.readLine();
            return s == null ? null : s.trim();
        } catch (IOException | SecurityException e) { return null; }
    }
    private static int readInt(String path, int dflt) {
        String s = readLine(path);
        try { return s == null ? dflt : Integer.parseInt(s); } catch (NumberFormatException e) { return dflt; }
    }

    /** get: fill values, return status (0 ok, -1 unsupported). */
    synchronized int get(int id, int[] values) {
        if (id >= 0x1000) return -1;
        switch (id) {
            case 8: case 30: { int v = readInt(BL + "max_brightness", -1); if (v < 0) return -1; fill(values, v); return 0; }
            case 29: { int v = readInt(BL + "brightness", -1); if (v < 0) return -1; fill(values, v); return 0; }
            default:
                if (PROBE.contains(id)) return 0;   // zero-filled array
                int[] k = kept.get(id);
                if (k != null) { System.arraycopy(k, 0, values, 0, Math.min(k.length, values.length)); return 0; }
                return KEEP.contains(id) ? 0 : -1;
        }
    }
    private static void fill(int[] a, int v) { if (a.length > 0) a[0] = v; }

    synchronized int set(int id, int[] values) {
        if (id >= 0x1000 || values == null || !KEEP.contains(id)) return -1;
        kept.put(id, values.clone());
        return 0;
    }

    List<String> info(int id) {
        if (id == 9) {
            String s = readLine(DEVINFO_LCD);
            if (s != null && !s.isEmpty()) return Collections.singletonList(s);
        }
        return null;
    }

    @Override boolean call(int code, Parcel in, Parcel out, boolean oneway) {
        switch (code) {
            case 1: {   // int getDisplayPanelFeatureValue(int id, inout int[] values)
                int id = in.readInt(), len = in.readInt();
                if (len < 0 || len > 1024) throw new IllegalArgumentException("array length " + len);
                int[] values = new int[len];
                for (int i = 0; i < len && in.dataAvail() >= 4; i++) values[i] = in.readInt();
                int status = get(id, values);
                out.writeNoException(); out.writeInt(status); out.writeIntArray(values);
                return true;
            }
            case 2: {   // int setDisplayPanelFeatureValue(int id, in int[] values)
                int id = in.readInt();
                int[] values = in.createIntArray();
                if (values != null && values.length > 1024) throw new IllegalArgumentException("array length");
                int status = set(id, values);
                out.writeNoException(); out.writeInt(status);
                return true;
            }
            case 3: {   // int getDisplayPanelInfo(int id, out List<String> info); never a null list
                int id = in.readInt();
                List<String> info = info(id);
                out.writeNoException();
                out.writeInt(info == null ? -1 : 0);
                out.writeStringList(info == null ? Collections.singletonList("") : info);
                return true;
            }
            default: return false;
        }
    }
}
