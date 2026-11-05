package com.port.pipa.helper;

import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "Animations": two states for OplusLauncher's animation tier (persist.sys.oplus.anim_level).
 * The tile only writes global pipa_anim_level; pipa_port sets the property and restarts the launcher (an app cannot
 * set persist.sys.* properties).
 *  - Fast (tier 3, port default): wallpaper zoom off, lighter interruption handling (SF dropped frames 2.7 -> 0.3 %).
 *  - ColorOS (tier 1): ColorOS's own slower animations.
 * Blur stays on in both states: the ROM sets debug.systemui.gaussblur_level=2 (SystemUI) and the app feature
 * com.oplus.blur.support_upgrade_anim_material_blur (launcher dock and folders at tier 3), step 5g.
 * Tiers 2 and 4 are still possible with `settings put global pipa_anim_level N`; the tile shows them as Fast.
 * Needs WRITE_SECURE_SETTINGS (privapp whitelist in the ROM, pm grant on a test install).
 */
public final class AnimTile extends TileService {
    private static final String TAG = "PipaHelper.Anim";
    private static final String KEY = "pipa_anim_level";
    private static final int FAST = 3;
    private static final int COLOROS = 1;

    @Override
    public void onStartListening() {
        show(level());
    }

    @Override
    public void onClick() {
        int next = level() == COLOROS ? FAST : COLOROS;
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
        return Settings.Global.getInt(getContentResolver(), KEY, FAST) == COLOROS ? COLOROS : FAST;
    }

    private void show(int v) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Animations");
        t.setSubtitle(v == COLOROS ? "ColorOS" : "Fast");
        t.setState(v == COLOROS ? Tile.STATE_INACTIVE : Tile.STATE_ACTIVE);
        t.updateTile();
    }
}
