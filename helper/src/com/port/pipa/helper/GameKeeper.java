package com.port.pipa.helper;

import android.app.ActivityManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.util.Log;
import android.util.SparseBooleanArray;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.HashSet;
import java.util.Set;

/**
 * Game in the foreground -> global pipa_game_fg = 1, else 0. pipa_port reads it and selects Xiaomi's mi_thermald game
 * profile (/sys/class/thermal/thermal_message/sconfig, GAME_THERMAL_SCENE in config.prop). On HyperOS, PowerKeeper
 * sets that scene; on ColorOS nobody does, so games ran with the daily profile (CPU caps from 38 C skin).
 *
 * A game is an app with android:appCategory="game" (ApplicationInfo.CATEGORY_GAME, the flag Android's GameManager
 * uses). The foreground state comes from ActivityManager.addOnUidImportanceListener (system API, called by
 * reflection; needs PACKAGE_USAGE_STATS, privapp whitelist in the ROM): a callback when a uid crosses the
 * IMPORTANCE_FOREGROUND line, no polling. The setting is written only when the state changes.
 */
final class GameKeeper {
    private static final String TAG = "PipaHelper.Game";
    private static final String KEY = "pipa_game_fg";
    private static final int IMPORTANCE_FOREGROUND = 100;
    private static final boolean DEBUG = false;   // true: one log line per foreground change (logs need persist.sys.assert.panic=true)

    private final Context ctx;
    private final PackageManager pm;
    private final SparseBooleanArray isGameUid = new SparseBooleanArray();
    private final Set<Integer> fgGames = new HashSet<>();
    private int written = -1;

    GameKeeper(Context ctx) {
        this.ctx = ctx;
        this.pm = ctx.getPackageManager();
    }

    void start() {
        write(0);   // no game at start (boot, or a helper restart)
        try {
            ActivityManager am = ctx.getSystemService(ActivityManager.class);
            Class<?> lc = Class.forName("android.app.ActivityManager$OnUidImportanceListener");
            InvocationHandler h = (proxy, m, args) -> {
                if ("onUidImportance".equals(m.getName()) && args != null && args.length >= 2) {
                    onUidImportance((Integer) args[0], (Integer) args[1]);
                    return null;
                }
                switch (m.getName()) {
                    case "hashCode": return System.identityHashCode(proxy);
                    case "equals": return proxy == args[0];
                    case "toString": return "GameKeeper.listener";
                    default: return null;
                }
            };
            Object listener = Proxy.newProxyInstance(lc.getClassLoader(), new Class<?>[]{lc}, h);
            Method add = ActivityManager.class.getMethod("addOnUidImportanceListener", lc, int.class);
            add.invoke(am, listener, IMPORTANCE_FOREGROUND);
            Log.i(TAG, "listening for foreground games");
        } catch (Throwable t) {
            Log.w(TAG, "cannot listen for foreground apps: " + t);
        }
    }

    private synchronized void onUidImportance(int uid, int importance) {
        if (DEBUG && uid >= 10000) Log.d(TAG, "uid " + uid + " importance " + importance + " game " + isGame(uid));
        if (!isGame(uid)) return;
        boolean fg = importance <= IMPORTANCE_FOREGROUND;
        boolean changed = fg ? fgGames.add(uid) : fgGames.remove(uid);
        if (changed) write(fgGames.isEmpty() ? 0 : 1);
    }

    private boolean isGame(int uid) {
        int i = isGameUid.indexOfKey(uid);
        if (i >= 0) return isGameUid.valueAt(i);
        boolean game = false;
        String[] pkgs = pm.getPackagesForUid(uid);
        if (pkgs != null) {
            for (String p : pkgs) {
                try {
                    ApplicationInfo ai = pm.getApplicationInfo(p, 0);
                    // appCategory="game", or the old android:isGame="true" (FLAG_IS_GAME), as Android's GameManager
                    if (ai.category == ApplicationInfo.CATEGORY_GAME || (ai.flags & ApplicationInfo.FLAG_IS_GAME) != 0) {
                        game = true;
                        break;
                    }
                } catch (PackageManager.NameNotFoundException ignored) {
                }
            }
        }
        isGameUid.put(uid, game);
        return game;
    }

    private void write(int v) {
        if (v == written) return;
        try {
            Settings.Global.putInt(ctx.getContentResolver(), KEY, v);
            written = v;
            Log.i(TAG, "game in foreground -> " + v);
        } catch (SecurityException e) {
            Log.w(TAG, "cannot write " + KEY + ": " + e.getMessage());
        }
    }
}
