package pipa.hal;

import android.os.*;
import java.lang.reflect.Method;
import java.util.*;

/**
 * One host process for all pipa HAL shims (one ART runtime, one binder pool: less RAM than one process per HAL).
 *   app_process /system/bin pipa.hal.HalHost host gameopt,panel,...      serves pipa.hal.<key>
 * Keys: gameopt, panel, misc (this folder) and touch (maintainer/touchshim TouchService, step 4o; in this host it saves
 * one app_process). The cryptoeng shim stays a separate process on purpose: it keeps the privacy-password records.
 *   app_process /system/bin pipa.hal.HalHost register gameopt,panel,...  adds the official names (cross-process
 *                                                                         proxy, as the charger and touch shims)
 * A name that already has a server (for example a real HAL in a later vendor) is left alone.
 */
public final class HalHost {
    private static final String LOCAL = "pipa.hal.";

    /** The binder and its official name for one key. */
    static final class Shim {
        final Binder binder; final String name;
        Shim(Binder binder, String name) {
            if (!name.equals(officialName(key(name)))) throw new IllegalStateException("name table: " + name);
            this.binder = binder; this.name = name;
        }
        private static String key(String name) {
            for (String k : new String[] { "touch", "panel", "misc", "gameopt" })
                if (officialName(k).equals(name)) return k;
            throw new IllegalStateException("not in the name table: " + name);
        }
    }
    static Shim shim(String key) {
        if (key.equals("touch"))
            return new Shim(new pipa.touch.TouchService("/system_ext/pipa_port/xiaomi_touch_ioctl"),
                            pipa.touch.TouchService.NAME);
        AidlService s = make(key);
        return new Shim(s, s.name());
    }
    /** Official names without building a service (the registrar must not start a shim's threads or replay its state). */
    static String officialName(String key) {
        switch (key) {
            case "touch": return pipa.touch.TouchService.NAME;
            case "panel": return "vendor.oplus.hardware.displaypanelfeature.IDisplayPanelFeature/default";
            case "misc": return "vendor.oplus.hardware.misc.IOplusMisc/default";
            case "gameopt": return "vendor.oplus.hardware.gameopt.IGameOptHalService/default";
            default: throw new IllegalArgumentException("unknown shim " + key);
        }
    }

    static AidlService make(String key) {
        switch (key) {
            case "panel": return new PanelFeatureService();
            case "misc": return new MiscService();
            case "gameopt": return new GameOptService();
            default: throw new IllegalArgumentException("unknown shim " + key);
        }
    }

    private static Method sm(String name, Class<?>... args) throws Exception {
        return Class.forName("android.os.ServiceManager").getMethod(name, args);
    }
    static IBinder check(String name) throws Exception {
        return (IBinder) sm("checkService", String.class).invoke(null, name);
    }
    private static void add(String name, IBinder binder) throws Exception {
        sm("addService", String.class, IBinder.class).invoke(null, name, binder);
    }
    private static void maxBinderThreads(int n) {
        try {   // the default pool (15) is not needed for these small services
            Class.forName("com.android.internal.os.BinderInternal").getMethod("setMaxThreads", int.class)
                .invoke(null, n);
        } catch (Throwable t) { System.err.println("setMaxThreads: " + t); }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("usage: host|register <key,key,...>");
        String[] keys = args[1].split(",");
        if (args[0].equals("register")) {
            for (String key : keys) {
                String official = officialName(key);
                if (check(official) != null) { System.out.println("exists, skipped: " + official); continue; }
                IBinder proxy = null;
                for (int i = 0; i < 30 && proxy == null; i++) {
                    proxy = check(LOCAL + key);
                    if (proxy == null) Thread.sleep(1000);
                }
                if (proxy == null) { System.out.println("host not ready: " + key); continue; }
                add(official, proxy);
                IBinder got = check(official);
                System.out.println((got != null ? "registered " : "FAILED ") + official);
            }
            return;
        }
        maxBinderThreads(4);
        Looper.prepare();   // the main thread only waits; binder threads serve the calls
        for (String key : keys) {
            if (check(LOCAL + key) != null) throw new IllegalStateException("host already runs: " + key);
            add(LOCAL + key, shim(key).binder);
        }
        System.out.println("pipa HAL host ready: " + String.join(",", keys));
        Looper.loop();
    }
}
