package com.port.pipa.helper;

import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "Logs" (helper 1.2, step 5x): Quiet or Verbose system logs.
 * The tile only writes global pipa_verbose_logs (0/1); pipa_port sets persist.log.tag (an app cannot set persist.*
 * properties): Quiet = "I" (debug and verbose lines are dropped in each process, errors/warnings/crashes stay),
 * Verbose = cleared (Android's default). Use Verbose before you capture logs for a bug report.
 * Needs WRITE_SECURE_SETTINGS (privapp whitelist in the ROM, pm grant on a test install).
 */
public final class LogTile extends TileService {
    private static final String TAG = "PipaHelper.Logs";
    private static final String KEY = "pipa_verbose_logs";

    @Override
    public void onStartListening() {
        show(verbose());
    }

    @Override
    public void onClick() {
        boolean next = !verbose();
        try {
            Settings.Global.putInt(getContentResolver(), KEY, next ? 1 : 0);
            Log.i(TAG, "verbose logs -> " + next);
        } catch (SecurityException e) {
            Log.w(TAG, "cannot write " + KEY + " (WRITE_SECURE_SETTINGS missing): " + e.getMessage());
            return;
        }
        show(next);
    }

    private boolean verbose() {
        return Settings.Global.getInt(getContentResolver(), KEY, 0) == 1;
    }

    private void show(boolean v) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Logs");
        t.setSubtitle(v ? "Verbose" : "Quiet");
        t.setState(v ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.updateTile();
    }
}
