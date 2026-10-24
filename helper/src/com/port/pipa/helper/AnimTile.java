package com.port.pipa.helper;

import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "Animations": picks OplusLauncher's animation tier (persist.sys.oplus.anim_level). The tile
 * only writes global pipa_anim_level; pipa_port sets the property and restarts the launcher (an app cannot set
 * persist.sys.* properties). Tier 3 is the port default: SF dropped frames 2.7 -> 0.3 % in app opens; tier 2 keeps
 * every parallel-animation path; 1 is ColorOS's own; 4 uses light animations without full-scene continuity.
 * Needs WRITE_SECURE_SETTINGS (privapp whitelist in the ROM, pm grant on a test install).
 */
public final class AnimTile extends TileService {
    private static final String TAG = "PipaHelper.Anim";
    private static final String KEY = "pipa_anim_level";
    private static final int DEFAULT = 3;
    private static final int[] NEXT = {0, 4, 1, 2, 3};   // tap order 3 -> 2 -> 1 -> 4 -> 3

    @Override
    public void onStartListening() {
        show(level());
    }

    @Override
    public void onClick() {
        int next = NEXT[level()];
        try {
            Settings.Global.putInt(getContentResolver(), KEY, next);
            Log.i(TAG, "animation tier -> " + next);
        } catch (SecurityException e) {
            Log.w(TAG, "cannot write " + KEY + " (WRITE_SECURE_SETTINGS missing): " + e.getMessage());
            return;
        }
        show(next);
    }

    private int level() {
        int v = Settings.Global.getInt(getContentResolver(), KEY, DEFAULT);
        return v >= 1 && v <= 4 ? v : DEFAULT;
    }

    private void show(int v) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Animations " + v);
        t.setSubtitle(v == 3 ? "Smooth" : v == 2 ? "Parallel" : v == 1 ? "ColorOS" : "Light");
        t.setState(v == 1 ? Tile.STATE_INACTIVE : Tile.STATE_ACTIVE);
        t.updateTile();
    }
}
