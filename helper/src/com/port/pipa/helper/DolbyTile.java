package com.port.pipa.helper;

import android.database.ContentObserver;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "Dolby Atmos" (helper 3.1, BUGS 172), as the HyperOS Dolby tile: on = Dolby, off = the effect
 * used before Dolby on this output (Xiaomi Sound or Original; Original when none was chosen). ColorOS's own Dolby tile stays off: Settings disables it because
 * the OPPO Dolby features are not set (our Dolby runs through MiSound and DolbyKeeper). The choice goes through
 * DolbyKeeper.setUserEffect, so it is remembered per output like a choice in MiSound. Long press: MiSound
 * (TilePrefsActivity).
 */
public final class DolbyTile extends TileService {
    private static final String TAG = "PipaHelper.DolbyTile";
    private static final String KEY = "effect_implementer";
    private final ContentObserver observer = new ContentObserver(new Handler(Looper.getMainLooper())) {
        @Override
        public void onChange(boolean self) {
            show();
        }
    };

    @Override
    public void onStartListening() {
        getContentResolver().registerContentObserver(Settings.Global.getUriFor(KEY), false, observer);
        show();
    }

    @Override
    public void onStopListening() {
        getContentResolver().unregisterContentObserver(observer);
    }

    @Override
    public void onClick() {
        DolbyKeeper k = DolbyKeeper.instance;
        if (k == null) {
            Log.w(TAG, "no DolbyKeeper in this process");
            return;
        }
        String next = on() ? k.offEffect() : "dolby"; // off = the effect used before Dolby (Xiaomi Sound or Original)
        k.setUserEffect(next);
        show(next.equals("dolby"));
    }

    private boolean on() {
        return "dolby".equals(Settings.Global.getString(getContentResolver(), KEY));
    }

    private void show() {
        show(on());
    }

    private void show(boolean on) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Dolby Atmos");
        t.setSubtitle(on ? "On" : "misound".equals(Settings.Global.getString(getContentResolver(), KEY)) ? "Xiaomi Sound" : "Off");
        t.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.updateTile();
    }
}
