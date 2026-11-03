package pipa.hal;

import android.os.*;
import java.io.*;

/**
 * vendor.oplus.hardware.misc.IOplusMisc/default, AIDL V1 (notes/cloud/MISC-SENSOR.md part A). The donor service maps
 * 128 OPPO node flags to /proc, /sys and /dev paths of the OPPO kernel. pipa has the same meaning for none of them,
 * except flag 83 (/proc/devinfo/lcd, panel make and version for the colour-mode config) when pipa has that file.
 *  - isMiscNodeSupport: 1 only for a flag in SUPPORTED whose pipa node exists (callers need > 0), else -1.
 *  - miscReadNodeFile: the content of that node (max 256 bytes), else "" (never null).
 *  - miscWriteNodeFile: -1. OPPO flag numbers name other things on pipa; no passthrough.
 *  - saveCalibrationData: false. The donor writes /mnt/vendor/persist; that could damage pipa factory data.
 * Value on pipa: with an AIDL misc, OplusEyeProtectLcdInfoHelper and AlertSliderHw do not take the HIDL
 * getService(true) fallback, which waits for ever when the pipa vendor declares the HIDL instance (lshal check).
 */
final class MiscService extends AidlService {
    private static final int[] SUPPORTED_FLAG = { 83 };
    private static final String[] SUPPORTED_PATH = { "/proc/devinfo/lcd" };

    MiscService() {
        super("vendor.oplus.hardware.misc.IOplusMisc", 1, "a899a863d8a7e0b5ed35ced2275f2ba68aaad329");
    }

    private static String path(int device, int flag) {
        if (device != 0) return null;
        for (int i = 0; i < SUPPORTED_FLAG.length; i++)
            if (SUPPORTED_FLAG[i] == flag && new File(SUPPORTED_PATH[i]).canRead()) return SUPPORTED_PATH[i];
        return null;
    }

    private static String read(String path) {
        if (path == null) return "";
        try (InputStream in = new FileInputStream(path)) {
            byte[] b = new byte[256];
            int n = 0, r;
            while (n < b.length && (r = in.read(b, n, b.length - n)) > 0) n += r;
            return new String(b, 0, n, java.nio.charset.StandardCharsets.UTF_8);
        } catch (IOException | SecurityException e) { return ""; }
    }

    @Override boolean call(int code, Parcel in, Parcel out, boolean oneway) {
        switch (code) {
            case 1: out.writeNoException(); out.writeInt(0); return true;                 // initialize: OK
            case 2: { int d = in.readInt(), f = in.readInt();                               // isMiscNodeSupport
                out.writeNoException(); out.writeInt(path(d, f) != null ? 1 : -1); return true; }
            case 3: { int d = in.readInt(), f = in.readInt();                               // miscReadNodeFile
                out.writeNoException(); out.writeString(read(path(d, f))); return true; }
            case 4: in.readInt(); in.readInt(); in.readString();                            // miscWriteNodeFile
                out.writeNoException(); out.writeInt(-1); return true;
            case 5: in.readInt(); in.createByteArray(); in.readInt();                       // saveCalibrationData
                out.writeNoException(); out.writeBoolean(false); return true;
            default: return false;
        }
    }
}
