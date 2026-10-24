package com.port.pipa.helper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.audiofx.AudioEffect;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.UUID;

/**
 * B10: keeps Xiaomi's Dolby effect (DAP) alive on the global output mix and re-applies its saved
 * on/off state at boot.
 *
 * On HyperOS the global DolbyAudioEffect is held in system_server (miui-services
 * DolbyEffectController). The port has no such holder: only MiSound creates it, when its page is
 * opened, and the effect disappears when MiSound's process is killed. This keeper holds a
 * low-priority handle so the effect always exists; MiSound (priority 0) still takes control when
 * the user opens it, and control falls back here when MiSound goes away.
 *
 * Protocol copied from MiSound's wrapper (class e.a): effect uuid DAP, type EFFECT_TYPE_NULL;
 * "DS on" is param 5, set value {0, 1, on}, get value {0} -> int at offset 0 (> 0 = on);
 * all ints little-endian. setParameter/getParameter(int, byte[]) are hidden API, reached by
 * reflection as MiSound does.
 */
final class DolbyKeeper {
    private static final String TAG = "PipaHelper.Dolby";
    private static final UUID DAP = UUID.fromString("9d4921da-8225-4f29-aefa-39537a04bcaa");
    private static final UUID TYPE_NULL = UUID.fromString("ec7178ec-e5e1-4432-a3f4-4657e6795210");
    private static final int PARAM_DS_ON = 5;
    private static final int PRIORITY = -1; // below MiSound (0), so its toggle keeps control
    private static final int MAX_TRIES = 20; // creation retries per trigger, 3 s apart
    private static final long RETRY_MS = 3000;

    private final Context ctx;
    private final Handler handler;
    private AudioEffect fx;
    private Method setParam, getParam;
    private int tries;

    DolbyKeeper(Context ctx) {
        this.ctx = ctx;
        HandlerThread t = new HandlerThread("dolby-keeper");
        t.start();
        handler = new Handler(t.getLooper());
    }

    void start() {
        // Cheap health check whenever the screen turns on (audioserver restarts kill the handle).
        ctx.registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                trigger();
            }
        }, new IntentFilter(Intent.ACTION_SCREEN_ON), null, handler);
        trigger();
    }

    private void trigger() {
        handler.removeCallbacks(this::ensure);
        tries = 0;
        handler.post(this::ensure);
    }

    private void ensure() {
        if (fx != null && readDsOn() < 0) {
            Log.w(TAG, "effect handle dead, recreating");
            release();
        }
        if (fx == null && !create()) {
            if (++tries < MAX_TRIES) {
                handler.postDelayed(this::ensure, RETRY_MS);
            } else {
                Log.e(TAG, "giving up until the next screen-on");
            }
            return;
        }
        apply();
    }

    private boolean create() {
        try {
            // AudioEffect(UUID type, UUID uuid, int priority, int audioSession) is hidden API.
            Constructor<AudioEffect> c = AudioEffect.class.getConstructor(
                    UUID.class, UUID.class, int.class, int.class);
            setParam = AudioEffect.class.getMethod("setParameter", int.class, byte[].class);
            getParam = AudioEffect.class.getMethod("getParameter", int.class, byte[].class);
            fx = c.newInstance(TYPE_NULL, DAP, PRIORITY, 0);
            fx.setControlStatusListener((effect, control) -> {
                Log.i(TAG, "control " + control);
                if (control) handler.post(this::apply);
            });
            Log.i(TAG, "DAP created on session 0, control " + fx.hasControl());
            return true;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            Log.w(TAG, "DAP create failed: " + cause);
            fx = null;
            return false;
        }
    }

    /** Make the effect's enabled state match the saved DS state, when we hold control. */
    private void apply() {
        if (fx == null || !fx.hasControl()) return;
        int on = readDsOn();
        if (on < 0) return;
        boolean want = on > 0;
        try {
            if (fx.getEnabled() != want) {
                setDsOn(want);
                fx.setEnabled(want);
                Log.i(TAG, "applied saved state: " + (want ? "on" : "off"));
            }
        } catch (IllegalStateException e) {
            Log.w(TAG, "apply failed: " + e);
        }
    }

    private int readDsOn() {
        byte[] value = new byte[12];
        try {
            int r = (Integer) getParam.invoke(fx, PARAM_DS_ON, value);
            if (r < 0) return -1;
        } catch (ReflectiveOperationException | IllegalStateException e) {
            return -1;
        }
        return (value[0] & 0xff) | (value[1] & 0xff) << 8 | (value[2] & 0xff) << 16
                | (value[3] & 0xff) << 24;
    }

    private void setDsOn(boolean on) {
        byte[] value = new byte[12];
        System.arraycopy(le(0), 0, value, 0, 4);
        System.arraycopy(le(1), 0, value, 4, 4);
        System.arraycopy(le(on ? 1 : 0), 0, value, 8, 4);
        try {
            int r = (Integer) setParam.invoke(fx, PARAM_DS_ON, value);
            if (r != AudioEffect.SUCCESS) Log.w(TAG, "setDsOn(" + on + ") = " + r);
        } catch (ReflectiveOperationException e) {
            Log.w(TAG, "setDsOn failed: " + e.getCause());
        }
    }

    private void release() {
        try {
            fx.release();
        } catch (RuntimeException ignored) {
        }
        fx = null;
    }

    private static byte[] le(int v) {
        return new byte[] {(byte) v, (byte) (v >> 8), (byte) (v >> 16), (byte) (v >> 24)};
    }
}
