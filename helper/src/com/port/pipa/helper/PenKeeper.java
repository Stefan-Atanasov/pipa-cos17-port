package com.port.pipa.helper;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.database.ContentObserver;
import android.net.Uri;
import android.os.Handler;
import android.os.HandlerThread;
import android.provider.Settings;
import android.util.Log;

/**
 * B3: Xiaomi Smart Pen battery, the way HyperOS shows it: a short pill at the top of the screen when
 * the pen is docked or taken out (PenPill; ColorOS refuses heads-up banners from this app), and a
 * low-battery notification. ColorOS's own pen UI only knows OPPO pens.
 *
 * The vendor sysfs nodes are root-only, so power-tune's pen watcher publishes them as
 * global pipa_pen_state = "<connected> <docked> <soc>" (or "0" without a pen). The soc comes
 * from the reverse charger, so it only updates while the pen is docked.
 */
final class PenKeeper {
    private static final String TAG = "PipaHelper.Pen";
    private static final String KEY = "pipa_pen_state";
    private static final String CH_LOW = "pen_low";
    private static final int ID_LOW = 2;
    private static final int LOW_SOC = 15;

    private final Context ctx;
    private final NotificationManager nm;
    private final Handler handler;
    private final PenPill pill;
    private boolean connected, docked;
    private int soc = -1;
    private boolean first = true;

    PenKeeper(Context ctx) {
        this.ctx = ctx;
        nm = ctx.getSystemService(NotificationManager.class);
        HandlerThread t = new HandlerThread("pen-keeper");
        t.start();
        handler = new Handler(t.getLooper());
        pill = new PenPill(ctx);
    }

    void start() {
        NotificationChannel low = new NotificationChannel(CH_LOW,
                "Pen battery low", NotificationManager.IMPORTANCE_HIGH);
        low.setShowBadge(false);
        nm.deleteNotificationChannel("pen_popup"); // 0.2 test channel; banners are refused (pill instead)
        nm.createNotificationChannel(low);

        Uri uri = Settings.Global.getUriFor(KEY);
        ctx.getContentResolver().registerContentObserver(uri, false, new ContentObserver(handler) {
            @Override
            public void onChange(boolean self) {
                update();
            }
        });
        handler.post(this::update);
    }

    private void update() {
        String s = Settings.Global.getString(ctx.getContentResolver(), KEY);
        String[] f = s == null ? new String[] {"0"} : s.trim().split("\\s+");
        boolean c = "1".equals(f[0]);
        boolean d = c && f.length > 1 && "1".equals(f[1]);
        int b = soc;
        if (c && f.length > 2) {
            try {
                b = Integer.parseInt(f[2]);
            } catch (NumberFormatException ignored) {
            }
        }
        boolean dockChanged = c && (d != docked || c != connected);
        boolean socChanged = b != soc;
        connected = c;
        docked = d;
        soc = b;
        // At process start only remember the state; pop-ups are for changes.
        if (first) {
            first = false;
            lowAlert();
            return;
        }
        if (!c) {
            nm.cancel(ID_LOW);
            return;
        }
        if (dockChanged) {
            Log.i(TAG, (d ? "docked" : "undocked") + ", soc " + b);
            popup(false);
        } else if (socChanged) {
            popup(true); // refresh a pill still on screen with the fresh reading
        }
        lowAlert();
    }

    private void popup(boolean refresh) {
        String pct = soc >= 0 ? soc + " %" : "";
        String state = docked ? (soc >= 100 ? "Charged" : "Charging") : "Pen";
        String text = pct.isEmpty() ? state : pct + " · " + state;
        if (refresh && !pill.isShowing()) return;
        pill.show(text, docked);
    }

    private void lowAlert() {
        if (!connected || docked || soc < 0 || soc > LOW_SOC) {
            nm.cancel(ID_LOW);
            return;
        }
        Notification n = new Notification.Builder(ctx, CH_LOW)
                .setSmallIcon(R.drawable.ic_pen)
                .setContentTitle("Pen battery low · " + soc + " %")
                .setContentText("Attach the pen to charge it")
                .setCategory(Notification.CATEGORY_STATUS)
                .setOnlyAlertOnce(true)
                .build();
        nm.notify(ID_LOW, n);
    }
}
