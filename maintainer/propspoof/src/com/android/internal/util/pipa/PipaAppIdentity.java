package com.android.internal.util.pipa;

import android.content.Context;
import android.os.Build;
import android.util.Log;

import java.lang.reflect.Field;

/**
 * Per-app device identity (port step 3o). Instrumentation.newApplication calls set() in each app process before the
 * Application class loads. Only the apps below see another device; all other apps see the real Build values.
 * - Netflix: Pixel 6. Netflix sends enableWidevineL1 only for whitelisted models (BUGS-TODO 28); pipa's Widevine is L1.
 * - Google Photos: Pixel XL. Photos gives unlimited original-quality backup to the Pixel XL.
 * - Games (BUGS-TODO 62): a gaming device, so that the game offers its high frame rates. Many games pick the frame-rate
 *   menu from a model list (often from their server). Only BRAND, MANUFACTURER, DEVICE, PRODUCT and MODEL change; the
 *   fingerprint stays real (null = keep the real value).
 */
public final class PipaAppIdentity {
    private static final String TAG = "PipaAppIdentity";

    // BRAND, MANUFACTURER, DEVICE, PRODUCT, MODEL, FINGERPRINT
    private static final String[] PIXEL_6 = {
        "google", "Google", "oriole", "oriole", "Pixel 6",
        "google/oriole/oriole:13/TQ3A.230805.001/10316531:user/release-keys"
    };
    private static final String[] PIXEL_XL = {
        "google", "Google", "marlin", "marlin", "Pixel XL",
        "google/marlin/marlin:10/QP1A.191005.007.A3/5972272:user/release-keys"
    };
    // Games (BUGS-TODO 62). Order: BRAND, MANUFACTURER, DEVICE, PRODUCT, MODEL, FINGERPRINT; null = real value.
    // Device per game from crDroid PixelPropsUtils (15.0 branch, Apache-2.0, fetched 2026-11-03; it sets only these
    // fields), except the RedMagic Nova entries (ours: tested on pipa for Racing Master and PUBG).
    // nubia RedMagic Nova gaming tablet (model NP03J; nubia uses model = device, as NX769J on the RedMagic 9 Pro)
    private static final String[] REDMAGIC_NOVA = { "nubia", "nubia", "NP03J", "NP03J", "NP03J", null };
    private static final String[] ROG6 = { "asus", "asus", "AI2201", null, "ASUS_AI2201", null };
    private static final String[] ROG6D = { "asus", "asus", "AI2203_C", null, "ASUS_AI2203_C", null };
    private static final String[] LENOVO_Y700 = { null, "lenovo", null, null, "Lenovo TB-9707F", null };
    private static final String[] OP8P = { null, "OnePlus", null, null, "IN2020", null };
    private static final String[] OP9P = { null, "OnePlus", null, null, "LE2123", null };
    private static final String[] MI11TP = { null, "Xiaomi", null, null, "2107113SI", null };
    private static final String[] MI13P = { "Xiaomi", "Xiaomi", null, null, "2210132C", null };
    private static final String[] POCO_F5 = { null, "Xiaomi", null, null, "23049PCD8G", null };
    private static final String[] BS4 = { null, "blackshark", null, null, "2SM-X706B", null };
    private static final String[] S24U = { "samsung", "samsung", null, null, "SM-S928B", null };

    // { profile, packages... }
    private static final Object[][] GAMES = {
        { REDMAGIC_NOVA, new String[] {
            "com.netease.dfjsna",            // Racing Master: tested 2026-11-03, HFR enable nil -> true
            "com.tencent.ig",                // PUBG Mobile: tested 2026-11-03 (user), "Ultra Extreme" frame rate shows
            "com.pubg.imobile", "com.pubg.krmobile", "com.rekoo.pubgm", "com.tencent.tmgp.pubgmhd",
            "com.vng.pubgmobile",            // PUBG regional builds (same game; crDroid: S24 Ultra)
            "com.tencent.tmgp.dfm",          // Delta Force (CN): not tested
        } },
        { ROG6, new String[] { "com.ea.gp.fifamobile", "com.gameloft.android.ANMP.GloftA9HM",
            "com.madfingergames.legends", "com.pearlabyss.blackdesertm", "com.pearlabyss.blackdesertm.gl" } },
        { ROG6D, new String[] { "com.proxima.dfm" } },
        { LENOVO_Y700, new String[] { "com.activision.callofduty.shooter", "com.garena.game.codm",
            "com.tencent.tmgp.kr.codm", "com.vng.codmvn" } },
        { OP8P, new String[] { "com.netease.lztgglobal", "com.riotgames.league.wildrift",
            "com.riotgames.league.wildrifttw", "com.riotgames.league.wildriftvn",
            "com.riotgames.league.teamfighttactics", "com.riotgames.league.teamfighttacticstw",
            "com.riotgames.league.teamfighttacticsvn" } },
        { OP9P, new String[] { "com.epicgames.fortnite", "com.epicgames.portal", "com.tencent.lolm" } },
        { MI11TP, new String[] { "com.ea.gp.apexlegendsmobilefps", "com.levelinfinite.hotta.gp",
            "com.supercell.clashofclans", "com.vng.mlbbvn" } },
        { MI13P, new String[] { "com.levelinfinite.sgameGlobal", "com.tencent.tmgp.sgame" } },
        { POCO_F5, new String[] { "com.dts.freefiremax", "com.dts.freefireth", "com.mobile.legends" } },
        { BS4, new String[] { "com.proximabeta.mf.uamo" } },
        { S24U, new String[] { "com.blizzard.diablo.immortal" } },
    };

    private static final String[] FIELDS = { "BRAND", "MANUFACTURER", "DEVICE", "PRODUCT", "MODEL", "FINGERPRINT" };

    private PipaAppIdentity() {}

    public static void set(Context context) {
        if (context == null) return;
        String pkg = context.getPackageName();
        String[] id;
        if ("com.netflix.mediaclient".equals(pkg)) {
            id = PIXEL_6;
        } else if ("com.google.android.apps.photos".equals(pkg)) {
            id = PIXEL_XL;
        } else {
            id = gameProfile(pkg);
            if (id == null) return;
        }
        for (int i = 0; i < FIELDS.length; i++) {
            if (id[i] == null) continue;
            try {
                setStatic(Build.class.getDeclaredField(FIELDS[i]), id[i]);
            } catch (Throwable t) {
                Log.e(TAG, "cannot set Build." + FIELDS[i], t);
                return;
            }
        }
        Log.i(TAG, pkg + " -> " + Build.MODEL);
    }

    private static String[] gameProfile(String pkg) {
        for (Object[] g : GAMES) {
            for (String p : (String[]) g[1]) if (p.equals(pkg)) return (String[]) g[0];
        }
        return null;
    }

    // Android 17 refuses Field.set() on a static final field. ART keeps static fields in the Class object, so write
    // the field at its offset with Unsafe (hidden Field.getOffset(); this class is in the boot class path).
    private static void setStatic(Field f, Object value) throws Exception {
        Class<?> u = Class.forName("sun.misc.Unsafe");
        Field theUnsafe = u.getDeclaredField("theUnsafe");
        theUnsafe.setAccessible(true);
        Object unsafe = theUnsafe.get(null);
        long offset = ((Number) Field.class.getDeclaredMethod("getOffset").invoke(f)).longValue();
        u.getMethod("putObjectVolatile", Object.class, long.class, Object.class)
                .invoke(unsafe, f.getDeclaringClass(), offset, value);
    }
}
