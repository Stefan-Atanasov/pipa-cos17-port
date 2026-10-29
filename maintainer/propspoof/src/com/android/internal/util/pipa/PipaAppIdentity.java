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
            return;
        }
        for (int i = 0; i < FIELDS.length; i++) {
            try {
                setStatic(Build.class.getDeclaredField(FIELDS[i]), id[i]);
            } catch (Throwable t) {
                Log.e(TAG, "cannot set Build." + FIELDS[i], t);
                return;
            }
        }
        Log.i(TAG, pkg + " -> " + Build.MODEL);
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
