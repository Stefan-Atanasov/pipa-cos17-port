package com.port.pipa.helper;

import android.content.Context;
import android.database.ContentObserver;
import android.os.Handler;
import android.os.HandlerThread;
import android.provider.Settings;
import android.util.Log;

/**
 * B14: magnetic case. pipa's hall is a SW_LID switch, so Android's lid handling works, but
 * PhoneWindowManager sleeps on close only with global lid_behavior=1. ColorOS's own "lock with
 * cover" switch (global device_case_enabled) waits for an OPPO hall sensor pipa lacks and does
 * nothing, so this mirrors it into lid_behavior the moment it changes (a 15 s poll in the module
 * applied the old value when the case was closed right after flipping the switch).
 * Needs WRITE_SECURE_SETTINGS (privapp whitelist in the ROM, pm grant on a test install).
 */
final class LidKeeper {
    private static final String TAG = "PipaHelper.Lid";
    private static final String SWITCH = "device_case_enabled";
    private static final String LID = "lid_behavior";

    private final Context ctx;
    private final Handler handler;

    LidKeeper(Context ctx) {
        this.ctx = ctx;
        HandlerThread t = new HandlerThread("lid-keeper");
        t.start();
        handler = new Handler(t.getLooper());
    }

    void start() {
        ctx.getContentResolver().registerContentObserver(Settings.Global.getUriFor(SWITCH), false,
                new ContentObserver(handler) {
                    @Override
                    public void onChange(boolean self) {
                        sync();
                    }
                });
        handler.post(this::sync);
    }

    private void sync() {
        int want = Settings.Global.getInt(ctx.getContentResolver(), SWITCH, 1) == 0 ? 0 : 1;
        if (Settings.Global.getInt(ctx.getContentResolver(), LID, -1) == want) return;
        try {
            Settings.Global.putInt(ctx.getContentResolver(), LID, want);
            Log.i(TAG, "lock with cover " + (want == 1 ? "on" : "off") + " -> lid_behavior " + want);
        } catch (SecurityException e) {
            Log.w(TAG, "cannot write lid_behavior (WRITE_SECURE_SETTINGS missing): " + e.getMessage());
        }
    }
}
