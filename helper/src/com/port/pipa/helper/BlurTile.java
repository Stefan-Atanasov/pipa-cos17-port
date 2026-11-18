package com.port.pipa.helper;

import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "Live blur" (helper 2.2, step 7x; user 2026-11-18): live or static blur behind the shade and
 * Quick Settings. ColorOS SystemUI (PlatformBlurManagerImpl) re-blurs the background 60 times a second (MOTION_60)
 * only on tier 1, or with persist.sys.oplus.systemui.dynamic_blur=true; otherwise it blurs one captured frame
 * (STATIC: a playing video freezes behind the panel). Live costs GPU while the panel is open: measured 2026-11-18,
 * QS open/close over a video, SystemUI janky frames 20 % live vs 4 % static. Default off.
 * The tile only writes global pipa_live_blur (0/1); pipa_port sets the property (an app cannot set persist.*).
 * SystemUI reads the property once at its start: the change applies after a reboot.
 */
public final class BlurTile extends TileService {
    private static final String TAG = "PipaHelper.Blur";
    private static final String KEY = "pipa_live_blur";
    private static final String PROP = "persist.sys.oplus.systemui.dynamic_blur";

    @Override
    public void onStartListening() {
        show(wanted());
    }

    @Override
    public void onClick() {
        boolean next = !wanted();
        try {
            Settings.Global.putInt(getContentResolver(), KEY, next ? 1 : 0);
            Log.i(TAG, "live blur -> " + next + " (after reboot)");
        } catch (SecurityException e) {
            Log.w(TAG, "cannot write " + KEY + " (WRITE_SECURE_SETTINGS missing): " + e.getMessage());
            return;
        }
        show(next);
    }

    private boolean wanted() {
        return Settings.Global.getInt(getContentResolver(), KEY, 0) == 1;
    }

    /** The value SystemUI runs with now (it read the property at its start). */
    private static boolean running() {
        try {
            Object v = Class.forName("android.os.SystemProperties").getMethod("get", String.class, String.class)
                    .invoke(null, PROP, "false");
            return "true".equals(v);
        } catch (ReflectiveOperationException | RuntimeException e) {
            return false;
        }
    }

    private void show(boolean on) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Live blur");
        String s = on ? "On" : "Off";
        if (on != running()) s += " (reboot)";
        t.setSubtitle(s);
        t.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.updateTile();
    }
}
