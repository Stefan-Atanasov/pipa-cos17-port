package com.port.pipa.helper;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.ContentObserver;
import android.net.Uri;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Log;

import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * helper 2.7 (8q): bug report logs and the Wi-Fi failure notice.
 * * Pipa Helper > System > Collect logs sets Global pipa_logs = 1; the pipa_port service writes a redacted tar.gz to
 *   /data/misc/pipa_logs (type pipa_logs_file, the only port data this app may read) and sets pipa_logs_file. This
 *   keeper copies it into Downloads (MediaStore: owned by this app, no storage permission), stores the content URI in
 *   Global pipa_logs_uri (read by the System page) and posts a notification that opens the share sheet.
 * * 8p: b1_capture.sh sets Global pipa_b1_last after a Wi-Fi failure snapshot: a notification asks to collect logs.
 * Both keys are watched with observers (no polling).
 */
final class LogsKeeper {
    static final String TAG = "PipaHelper.Logs";
    static final String KEY_FILE = "pipa_logs_file";
    static final String KEY_URI = "pipa_logs_uri";
    static final String KEY_B1 = "pipa_b1_last";
    private static final String DIR = "/data/misc/pipa_logs/";
    private static final String CH = "pipa_reports";
    private static final int ID_LOGS = 31;
    private static final int ID_WIFI = 32;

    private final Context ctx;
    private final NotificationManager nm;

    LogsKeeper(Context ctx) {
        this.ctx = ctx;
        this.nm = ctx.getSystemService(NotificationManager.class);
    }

    void start() {
        nm.createNotificationChannel(new NotificationChannel(CH, ctx.getString(R.string.logs_channel),
                NotificationManager.IMPORTANCE_DEFAULT));
        Handler h = new Handler(Looper.getMainLooper());
        ContentResolver cr = ctx.getContentResolver();
        cr.registerContentObserver(Settings.Global.getUriFor(KEY_FILE), false, new ContentObserver(h) {
            @Override public void onChange(boolean self) { new Thread(LogsKeeper.this::copyLogs, "pipa-logs").start(); }
        });
        cr.registerContentObserver(Settings.Global.getUriFor(KEY_B1), false, new ContentObserver(h) {
            @Override public void onChange(boolean self) { wifiNotice(); }
        });
    }

    /** the newest service file -> Downloads, once per file name */
    private synchronized void copyLogs() {
        ContentResolver cr = ctx.getContentResolver();
        String name = Settings.Global.getString(cr, KEY_FILE);
        if (name == null || !name.matches("pipa-logs-[0-9-]+\\.tar\\.gz")) return;
        String done = Settings.Global.getString(cr, KEY_URI);
        if (done != null && done.endsWith("#" + name)) return;
        ContentValues v = new ContentValues();
        v.put(MediaStore.Downloads.DISPLAY_NAME, name);
        v.put(MediaStore.Downloads.MIME_TYPE, "application/gzip");
        v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
        v.put(MediaStore.Downloads.IS_PENDING, 1);
        Uri uri = null;
        try {
            uri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (uri == null) throw new IllegalStateException("MediaStore insert failed");
            try (InputStream in = new FileInputStream(DIR + name); OutputStream out = cr.openOutputStream(uri)) {
                byte[] b = new byte[65536];
                for (int n; (n = in.read(b)) > 0; ) out.write(b, 0, n);
            }
            v.clear();
            v.put(MediaStore.Downloads.IS_PENDING, 0);
            cr.update(uri, v, null, null);
            Settings.Global.putString(cr, KEY_URI, uri + "#" + name);
            Log.i(TAG, "logs copied to Downloads: " + name);
            logsNotice(uri, name);
        } catch (Exception e) {
            Log.w(TAG, "copy " + name + " failed: " + e);
            if (uri != null) cr.delete(uri, null, null);
        }
    }

    static Intent shareIntent(Context c, Uri uri) {
        Intent send = new Intent(Intent.ACTION_SEND).setType("application/gzip")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_SUBJECT, "Pipa logs")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return Intent.createChooser(send, c.getString(R.string.logs_share)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }

    private void logsNotice(Uri uri, String name) {
        PendingIntent share = PendingIntent.getActivity(ctx, ID_LOGS, shareIntent(ctx, uri),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent issues = PendingIntent.getActivity(ctx, ID_LOGS + 100,
                new Intent(Intent.ACTION_VIEW, Uri.parse(PageActivity.REPO_ISSUES)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(ctx, CH)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(ctx.getString(R.string.logs_saved_title))
                .setContentText(ctx.getString(R.string.logs_saved_text, name))
                .setStyle(new Notification.BigTextStyle().bigText(ctx.getString(R.string.logs_saved_text, name)))
                .setContentIntent(share)
                .addAction(new Notification.Action.Builder(null, ctx.getString(R.string.logs_share), share).build())
                .addAction(new Notification.Action.Builder(null, ctx.getString(R.string.sys_bug), issues).build())
                .setAutoCancel(true)
                .build();
        nm.notify(ID_LOGS, n);
    }

    private static final long WIFI_NOTICE_GAP_MS = 6 * 3600 * 1000L;

    /** at most one notice per 6 h (the capture itself is limited to one per 10 min) */
    private void wifiNotice() {
        android.content.SharedPreferences p = ctx.getSharedPreferences("logs", Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        long last = p.getLong("wifi_notice", 0);
        if (last > 0 && now - last < WIFI_NOTICE_GAP_MS && now >= last) return;
        p.edit().putLong("wifi_notice", now).apply();
        Intent page = new Intent(ctx, PageActivity.class).putExtra(PageActivity.EXTRA_PAGE, "system")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pi = PendingIntent.getActivity(ctx, ID_WIFI, page,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new Notification.Builder(ctx, CH)
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle(ctx.getString(R.string.wifi_logged_title))
                .setContentText(ctx.getString(R.string.wifi_logged_text))
                .setStyle(new Notification.BigTextStyle().bigText(ctx.getString(R.string.wifi_logged_text)))
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build();
        nm.notify(ID_WIFI, n);
    }
}
