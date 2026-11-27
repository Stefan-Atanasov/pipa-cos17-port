package com.port.pipa.helper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.wifi.WifiManager;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.concurrent.Executor;

/**
 * Quick Settings tile "Hotspot" (helper 3.1, BUGS 172), as on HyperOS. ColorOS hides its own hotspot tile on Wi-Fi
 * only tablets (OplusHotspotTile.isAvailable: FeatureOption.isTabletWifi), but the hotspot works (Wi-Fi client +
 * hotspot at the same time). The tile starts and stops Wi-Fi tethering with the hotspot settings of Settings >
 * Personal hotspot: TetheringManager.startTethering / stopTethering (system API, reflection; TETHER_PRIVILEGED in the
 * privapp list). State: WifiManager.getWifiApState and the WIFI_AP_STATE_CHANGED broadcast while the panel is open.
 * Long press: Personal hotspot settings (TilePrefsActivity).
 */
public final class HotspotTile extends TileService {
    private static final String TAG = "PipaHelper.HotspotTile";
    private static final String AP_STATE_CHANGED = "android.net.wifi.WIFI_AP_STATE_CHANGED";
    private static final int AP_DISABLING = 10, AP_DISABLED = 11, AP_ENABLING = 12, AP_ENABLED = 13;
    private static final int TETHERING_WIFI = 0;
    private BroadcastReceiver receiver;

    @Override
    public void onStartListening() {
        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                show(i.getIntExtra("wifi_state", apState()));
            }
        };
        registerReceiver(receiver, new IntentFilter(AP_STATE_CHANGED), Context.RECEIVER_EXPORTED);
        show(apState());
    }

    @Override
    public void onStopListening() {
        if (receiver != null) {
            unregisterReceiver(receiver);
            receiver = null;
        }
    }

    @Override
    public void onClick() {
        int s = apState();
        boolean on = s == AP_ENABLED || s == AP_ENABLING;
        try {
            Object tm = getSystemService("tethering");
            Class<?> c = Class.forName("android.net.TetheringManager");
            if (on) {
                c.getMethod("stopTethering", int.class).invoke(tm, TETHERING_WIFI);
                show(AP_DISABLING);
            } else {
                Class<?> cb = Class.forName("android.net.TetheringManager$StartTetheringCallback");
                Object callback = Proxy.newProxyInstance(cb.getClassLoader(), new Class<?>[] {cb}, (p, m, a) -> {
                    if (m.getName().equals("onTetheringFailed")) {
                        Log.w(TAG, "start failed: " + (a != null && a.length > 0 ? a[0] : "?"));
                        show(apState());
                    }
                    return null;
                });
                Executor main = getMainExecutor();
                c.getMethod("startTethering", int.class, Executor.class, cb).invoke(tm, TETHERING_WIFI, main, callback);
                show(AP_ENABLING);
            }
            Log.i(TAG, on ? "stop" : "start");
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, (on ? "stop" : "start") + ": " + e);
        }
    }

    private int apState() {
        try {
            Method m = WifiManager.class.getMethod("getWifiApState");
            return (Integer) m.invoke(getSystemService(WifiManager.class));
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, "getWifiApState: " + e);
            return AP_DISABLED;
        }
    }

    private void show(int s) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Hotspot");
        boolean on = s == AP_ENABLED || s == AP_ENABLING;
        t.setSubtitle(s == AP_ENABLING ? "Turning on" : s == AP_DISABLING ? "Turning off" : on ? "On" : "Off");
        t.setState(on ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.updateTile();
    }
}
