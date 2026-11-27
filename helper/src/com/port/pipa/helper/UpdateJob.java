package com.port.pipa.helper;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import android.util.Log;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * ROM update check (helper 3.3). Reads latest.json of the public repo (release version, build number, date, links) and
 * compares its build number with the installed build (/system_ext/pipa_port/build: "pt151" or "pt150-noenc" -> 151, 150).
 * Event driven, like the stock updater: a daily JobScheduler job (any network, battery not low; the system batches it)
 * and "Check now" in Pipa Helper > System. One small GET, no download: a newer release only posts a notification.
 * Global keys: pipa_update_check (1 = daily check, the default), pipa_update_latest ("version|build|date|notes|downloads"
 * of the last good check), pipa_update_last (epoch s of the last good check), pipa_update_notified (build already shown).
 */
public final class UpdateJob extends JobService {
    static final String URL_LATEST =
            "https://raw.githubusercontent.com/Stefan-Atanasov/pipa-cos17-port/main/latest.json";
    static final String KEY_ON = "pipa_update_check";
    static final String KEY_LATEST = "pipa_update_latest";
    static final String KEY_LAST = "pipa_update_last";
    /** 3.4 install (service.sh ota_check): 1 = request, 2 = running, 3 = done (restart), 4 = failed */
    static final String KEY_OTA = "pipa_ota";
    static final String KEY_OTA_PAYLOAD = "pipa_ota_payload";
    static final String KEY_OTA_PROGRESS = "pipa_ota_progress";
    static final String KEY_OTA_ERROR = "pipa_ota_error";
    /** 3.6: the "ota" object of latest.json (raw JSON): payloads, each with mirrors */
    static final String KEY_LATEST_OTA = "pipa_update_ota";
    /** 3.7: HTTP code of the last check (-1 = no answer: offline or blocked); 404 = no latest.json published */
    static volatile int lastHttp;
    private static final String KEY_NOTIFIED = "pipa_update_notified";
    private static final int JOB_ID = 3301;
    private static final int NOTIF_ID = 3301;
    private static final String CH = "updates";
    private static final String TAG = "PipaHelper.Update";

    /** The latest release, from latest.json or from the stored copy of the last good check. */
    static final class Info {
        final String version, date, notes, downloads;
        final int build;
        /** 3.6: the "ota" object of latest.json (raw JSON, kept in KEY_LATEST_OTA); empty = no OTA */
        String ota = "";

        Info(String version, int build, String date, String notes, String downloads) {
            this.version = version;
            this.build = build;
            this.date = date;
            this.notes = notes;
            this.downloads = downloads;
        }

        /** An install for this tablet exists: a payload that fits the installed build, and encrypted /data. */
        boolean hasOta() {
            return encrypted() && !candidates(this).isEmpty();
        }

        String flat() {
            return version + "|" + build + "|" + date + "|" + notes + "|" + downloads;
        }

        static Info parse(String s) {
            if (s == null) return null;
            String[] p = s.split("\\|", -1);
            if (p.length != 5 && p.length != 9) return null;
            try {
                return new Info(p[0], Integer.parseInt(p[1]), p[2], p[3], p[4]);   // 9 fields: 3.4 OTA, ignored
            } catch (NumberFormatException e) {
                return null;
            }
        }
    }

    static Info stored(Context c) {
        Info i = Info.parse(Settings.Global.getString(c.getContentResolver(), KEY_LATEST));
        if (i != null) {
            String o = Settings.Global.getString(c.getContentResolver(), KEY_LATEST_OTA);
            i.ota = o == null ? "" : o;
        }
        return i;
    }

    /** One A/B payload of latest.json: from = the build it is a delta from (empty = full payload). */
    static final class Payload {
        String from = "", headers = "";
        long offset, size;
        final List<String> urls = new ArrayList<>();
    }

    /** /data is encrypted: the port payloads are built for it (a -noenc build would not start after the install). */
    static boolean encrypted() {
        return "encrypted".equals(Status.prop("ro.crypto.state"));
    }

    /**
     * The payloads to try, in order: the delta from the exact installed build first (small download), then the full
     * payloads. A delta only applies to the exact build it was made from (update_engine checks the source hashes);
     * the tag also names the variant ("pt165-noenc" is no "pt165").
     */
    static List<Payload> candidates(Info i) {
        List<Payload> deltas = new ArrayList<>(), full = new ArrayList<>();
        String tag = Status.build().trim();
        try {
            org.json.JSONArray a = new JSONObject(i.ota).getJSONArray("payloads");
            for (int k = 0; k < a.length(); k++) {
                JSONObject o = a.getJSONObject(k);
                Payload p = new Payload();
                p.from = o.optString("from");
                p.offset = o.optLong("offset", -1);
                p.size = o.optLong("size", -1);
                // service.sh format: ';' between the header lines; '|' '^' ' ' separate fields, payloads, mirrors
                p.headers = o.optString("headers").trim().replaceAll("[|^; \r]", "")
                        .replace("\n", ";");
                org.json.JSONArray u = o.optJSONArray("urls");
                for (int m = 0; u != null && m < u.length(); m++) {
                    String s = u.optString(m);
                    if (s.startsWith("https://") && !s.matches(".*[|^ ].*")) p.urls.add(s);
                }
                if (p.offset < 0 || p.size <= 0 || p.headers.isEmpty() || p.urls.isEmpty()) continue;
                if (p.from.isEmpty()) full.add(p);
                else if (p.from.equals(tag)) deltas.add(p);
            }
        } catch (Exception e) {
            return new ArrayList<>();
        }
        deltas.addAll(full);
        return deltas;
    }

    /**
     * Mirror speed probe: 1 MiB of the payload start with a range request. A mirror must answer 206 with the payload
     * magic "CrAU" (a quota or error page fails). Bytes per second, -1 = failed. Network thread only.
     */
    static double probe(String url, long offset) {
        HttpURLConnection h = null;
        try {
            long t0 = System.nanoTime();
            h = (HttpURLConnection) new URL(url).openConnection();
            h.setConnectTimeout(5000);
            h.setReadTimeout(8000);
            h.setUseCaches(false);
            h.setRequestProperty("User-Agent", "PipaHelper");
            h.setRequestProperty("Range", "bytes=" + offset + "-" + (offset + (1 << 20) - 1));
            if (h.getResponseCode() != 206) return -1;
            byte[] buf = new byte[16384], magic = new byte[4];
            int got = 0;
            try (InputStream in = h.getInputStream()) {
                for (int n; got < (1 << 20) && (n = in.read(buf)) > 0; ) {
                    for (int q = 0; q < n && got + q < 4; q++) magic[got + q] = buf[q];
                    got += n;
                    if (System.nanoTime() - t0 > 15_000_000_000L) break;
                }
            }
            if (got < 4 || !"CrAU".equals(new String(magic, StandardCharsets.US_ASCII))) return -1;
            return got / ((System.nanoTime() - t0) / 1e9);
        } catch (Exception e) {
            Log.w(TAG, "probe " + Uri.parse(url).getHost() + ": " + e);
            return -1;
        } finally {
            if (h != null) h.disconnect();
        }
    }

    /**
     * global pipa_ota_payload for service.sh ota_check: the payloads in order, '^' between them, each
     * "url url ...|offset|size|headers" with the mirrors by probe speed (failed probes last: they may work later).
     */
    static String payloadSetting(List<Payload> c) {
        StringBuilder sb = new StringBuilder();
        for (Payload p : c) {
            List<String> u = new ArrayList<>(p.urls);
            java.util.Map<String, Double> sp = new java.util.HashMap<>();
            for (String s : u) sp.put(s, probe(s, p.offset));
            u.sort((x, y) -> Double.compare(sp.get(y), sp.get(x)));
            Log.i(TAG, "mirrors " + (p.from.isEmpty() ? "full" : "delta from " + p.from) + ": " + sp);
            if (sb.length() > 0) sb.append('^');
            sb.append(String.join(" ", u)).append('|').append(p.offset).append('|').append(p.size).append('|')
                    .append(p.headers);
        }
        return sb.toString();
    }

    /** Daily job, persisted over reboots. Not rescheduled when it is already pending (keeps its period). */
    static void schedule(Context c) {
        JobScheduler js = c.getSystemService(JobScheduler.class);
        if (js == null || js.getPendingJob(JOB_ID) != null) return;
        js.schedule(new JobInfo.Builder(JOB_ID, new ComponentName(c, UpdateJob.class))
                .setPeriodic(TimeUnit.DAYS.toMillis(1), TimeUnit.HOURS.toMillis(6))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setRequiresBatteryNotLow(true)
                .setPersisted(true)
                .build());
    }

    /** Build number of the installed ROM, -1 when the build file has no "ptNNN". */
    static int installedBuild() {
        String b = Status.build();
        int i = b.indexOf("pt"), j = i + 2;
        if (i < 0) return -1;
        while (j < b.length() && Character.isDigit(b.charAt(j))) j++;
        try {
            return Integer.parseInt(b.substring(i + 2, j));
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    static boolean newer(Info i) {
        int b = installedBuild();
        return i != null && b > 0 && i.build > b;
    }

    /** Fetches latest.json and stores it. Null on any error. Network: never on the main thread. */
    static Info check(Context c) {
        HttpURLConnection h = null;
        lastHttp = -1;
        try {
            h = (HttpURLConnection) new URL(URL_LATEST).openConnection();
            h.setConnectTimeout(10000);
            h.setReadTimeout(10000);
            h.setUseCaches(false);
            h.setRequestProperty("User-Agent", "PipaHelper");   // not the default one with the device model
            lastHttp = h.getResponseCode();
            if (lastHttp != 200) {
                Log.w(TAG, "HTTP " + lastHttp);
                return null;
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            try (InputStream in = h.getInputStream()) {
                byte[] buf = new byte[4096];
                for (int n; (n = in.read(buf)) > 0 && out.size() < 16384; ) out.write(buf, 0, n);
            }
            JSONObject j = new JSONObject(out.toString(StandardCharsets.UTF_8.name()));
            Info i = new Info(j.getString("version"), j.getInt("build"), j.optString("date"),
                    j.optString("notes"), j.optString("downloads"));
            JSONObject o = j.optJSONObject("ota");
            i.ota = o == null ? "" : o.toString();
            ContentResolver cr = c.getContentResolver();
            Settings.Global.putString(cr, KEY_LATEST, i.flat());
            Settings.Global.putString(cr, KEY_LATEST_OTA, i.ota);
            Settings.Global.putLong(cr, KEY_LAST, System.currentTimeMillis() / 1000);
            return i;
        } catch (Exception e) {
            if (lastHttp != 200) lastHttp = -1;
            Log.w(TAG, "check failed: " + e);
            return null;
        } finally {
            if (h != null) h.disconnect();
        }
    }

    static Intent view(String url) {
        return new Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }

    /** One notification per new release (pipa_update_notified keeps the last build shown). */
    static void notifyIfNew(Context c, Info i) {
        ContentResolver cr = c.getContentResolver();
        if (!newer(i) || Settings.Global.getInt(cr, KEY_NOTIFIED, 0) >= i.build) return;
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CH, c.getString(R.string.upd_channel),
                NotificationManager.IMPORTANCE_DEFAULT));
        PendingIntent notes = PendingIntent.getActivity(c, NOTIF_ID, view(i.notes), PendingIntent.FLAG_IMMUTABLE);
        PendingIntent dl = PendingIntent.getActivity(c, NOTIF_ID + 1, view(i.downloads), PendingIntent.FLAG_IMMUTABLE);
        nm.notify(NOTIF_ID, new Notification.Builder(c, CH)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(c.getString(R.string.upd_new_title, i.version))
                .setContentText(c.getString(R.string.upd_new_text, i.date))
                .setContentIntent(notes)
                .addAction(new Notification.Action.Builder(null, c.getString(R.string.upd_downloads), dl).build())
                .setAutoCancel(true)
                .build());
        Settings.Global.putInt(cr, KEY_NOTIFIED, i.build);
    }

    @Override
    public boolean onStartJob(JobParameters p) {
        if (Settings.Global.getInt(getContentResolver(), KEY_ON, 1) == 0) return false;
        new Thread(() -> {
            Info i = check(this);
            notifyIfNew(this, i);
            jobFinished(p, false);   // periodic: the next run comes anyway, no retry storm when offline
        }, "pipa-update").start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters p) {
        return false;
    }
}
