package com.port.pipa.helper;

import android.content.Context;
import android.database.ContentObserver;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "Extra dim" (helper 3.2), as on Pixel and HyperOS: Android's Reduce bright colors
 * (ColorDisplayService, works on pipa: the SurfaceFlinger colour matrix dims the screen). ColorOS keeps the feature
 * but its Settings page is empty, so the switch and the intensity are here and in Pipa Helper > Effects.
 * Writes the AOSP Secure keys (WRITE_SECURE_SETTINGS, privapp list). Long press: Pipa Helper > Effects.
 */
public final class ExtraDimTile extends TileService {
    static final String KEY_ON = "reduce_bright_colors_activated";
    static final String KEY_LEVEL = "reduce_bright_colors_level";
    static final String KEY_KEEP = "reduce_bright_colors_persist_across_reboots";
    static final int DEFAULT_LEVEL = 50;
    private static final String TAG = "PipaHelper.ExtraDim";
    private final ContentObserver observer = new ContentObserver(new Handler(Looper.getMainLooper())) {
        @Override
        public void onChange(boolean self) {
            show();
        }
    };

    static boolean put(Context c, String key, int v) {
        try {
            return Settings.Secure.putInt(c.getContentResolver(), key, v);
        } catch (SecurityException e) {
            Log.w(TAG, "cannot write " + key + ": " + e.getMessage());
            return false;
        }
    }

    @Override
    public void onStartListening() {
        getContentResolver().registerContentObserver(Settings.Secure.getUriFor(KEY_ON), false, observer);
        getContentResolver().registerContentObserver(Settings.Secure.getUriFor(KEY_LEVEL), false, observer);
        show();
    }

    @Override
    public void onStopListening() {
        getContentResolver().unregisterContentObserver(observer);
    }

    @Override
    public void onClick() {
        boolean next = !on();
        if (put(this, KEY_ON, next ? 1 : 0)) Log.i(TAG, "extra dim -> " + next);
        show();
    }

    private boolean on() {
        return Settings.Secure.getInt(getContentResolver(), KEY_ON, 0) == 1;
    }

    private void show() {
        Tile t = getQsTile();
        if (t == null) return;
        boolean on = on();
        t.setLabel("Extra dim");
        t.setSubtitle(on ? Settings.Secure.getInt(getContentResolver(), KEY_LEVEL, DEFAULT_LEVEL) + " %" : "Off");
        t.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.updateTile();
    }
}
