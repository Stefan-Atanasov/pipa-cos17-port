package com.port.pipa.helper;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * Long press on a helper tile (ACTION_QS_TILE_PREFERENCES, helper 3.1): Dolby -> MiSound (as HyperOS), Hotspot ->
 * Personal hotspot settings, Extra dim -> Pipa Helper > Effects. Other tiles: the Pipa Helper app.
 */
public final class TilePrefsActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        ComponentName tile = getIntent().getParcelableExtra(Intent.EXTRA_COMPONENT_NAME, ComponentName.class);
        String cls = tile == null ? "" : tile.getClassName();
        Intent i;
        if (cls.endsWith(".DolbyTile")) {
            i = new Intent().setClassName("com.miui.misound", "com.miui.misound.HeadsetSettingsActivity");
        } else if (cls.endsWith(".ExtraDimTile")) {
            i = new Intent(this, PageActivity.class).putExtra(PageActivity.EXTRA_PAGE, "effects");
        } else if (cls.endsWith(".HotspotTile")) {
            i = new Intent("com.android.settings.WIFI_TETHER_SETTINGS");
        } else {
            i = new Intent(this, MainActivity.class);
        }
        try {
            startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (RuntimeException e) {
            Log.w("PipaHelper.TilePrefs", "cannot open " + i + ": " + e);
        }
        finish();
    }
}
