package com.port.pipa.helper;

import android.app.ActivityManager;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.database.ContentObserver;
import android.provider.Settings;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.media.AudioPlaybackConfiguration;
import android.media.audiofx.AudioEffect;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.Log;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;

/**
 * Dolby DAP on the global output mix (session 0), the way HyperOS system_server does it (miui-services).
 *
 * Holder (stock: AudioEffectCenter / BaseEffectPresenter.getDolbyAudioInstanceSafely): one long-lived DAP handle,
 * re-created when it is dead or missing. AudioFlinger destroys the session 0 chain when its output closes (pause,
 * idle), so the handle is checked on every playback start, every output device change, at boot and at screen-on.
 * Low priority (-1): MiSound (priority 0) takes control when the user opens it. 0.9: event driven; the old 60 s
 * screen-on poll is gone (with the screen off, music started after an idle output played without Dolby).
 *
 * Tuning device (stock: DolbyEffectController, non-spatializer path): on output device and music volume changes a
 * temporary DAP handle (priority 0, session 0) selects the tuning with setParameter(4, [int port][device id]) and is
 * released. Speaker: speaker_volume_high if music index > max * 10 / 15, else speaker_volume_low (both only when
 * vendor.audio.dolby.control.tunning.by.volume.support=true, else default_internal_speaker); wired headphone
 * default_headphone, Bluetooth default_bluetooth, USB default_usb. Same tuning as before: skipped.
 *
 * Effect per output device (stock: AudioEffectCenter.saveEffectForDevice / onDeviceChanged in system_server): the
 * user's choice in MiSound (Settings.Global effect_implementer: dolby / none = "Original" / misound) is remembered
 * for the device class it was made on (speaker, bluetooth_device, wiredHeadset_device, usb_device; Settings.Global
 * last_device), and re-applied when the output changes. No entry: Dolby, as stock's default. On stock the map lives in
 * persist.audio.effect.device_map, which MiSound (priv_app: neverallow on the property socket) cannot set; the helper
 * keeps it in its preferences. Applying an effect does what stock BaseEffectPresenter does: dolby = DS on + MiSound
 * effect off, misound = DS off + MiSound effect on, none = both off (1.5 only switched DS, so a remembered Dolby next
 * to an active MiSound effect processed the sound twice).
 * 1.6: only the user's choice is remembered: a change while MiSound is in the foreground and not within SETTLE_MS of
 * an output change. MiSound's own presenter (the porter put stock AudioEffectCenter into MiSound's dex) picks a default
 * at BOOT_COMPLETED and on device broadcasts while its process holds one (its map is always empty on the port): Dolby,
 * or MiSound when DAP is not up yet. 1.5 stored such a default as the user's choice (seen 2026-11-07: speaker became
 * "misound" after a restart). Now such a change is undone: the remembered effect is applied again.
 *
 * 1.7 (BUGS 102): boot re-check. The one-shot boot apply (onOutputChanged) can lose a race: DS state set before DMS /
 * libhwdap is ready (setParameter result was never checked), or MiSound's BOOT_COMPLETED default runs after it. apply()
 * then reads the half-set DS state as "saved" and turns the effect off, and nothing runs again. After BOOT_COMPLETED
 * (and when the process starts after boot) the remembered effect is checked twice, RECHECK_MS and RECHECK2_MS later,
 * and applied again when the effects do not match it. One-shot timers, no polling; skipped when the user changed the
 * effect in MiSound since the helper started.
 *
 * 1.8 (BUGS 108, tester beta8): after "clear recent apps" MiSound starts cold and its presenter writes its default
 * (misound) while its screen is in the foreground; 1.6/1.7 stored that as the user's choice. MiSound cannot keep its
 * own choice (priv_app cannot set persist.audio.effect.device_map), so every cold start brought the default back. Now a
 * change within OPEN_MS of MiSound's last ACTIVITY_RESUMED (UsageStatsManager, PACKAGE_USAGE_STATS) is MiSound's own
 * default and is undone; a real tap comes later.
 *
 * MiSound effect holder (stock: system_server holds it): one long-lived misoundfx handle on session 0, priority -1,
 * enabled only while effect_implementer is "misound"; event driven like the DAP holder (no polling).
 *
 * Protocol from MiSound's DolbyAudioEffect: "DS on" is param 5 with value {0, 1, on}; get value {0} at param 5.
 * setParameter/getParameter(int, byte[]) and the 4-argument constructor are hidden API (reflection, as MiSound).
 */
final class DolbyKeeper {
    private static final String TAG = "PipaHelper.Dolby";
    private static final UUID DAP = UUID.fromString("9d4921da-8225-4f29-aefa-39537a04bcaa");
    private static final UUID TYPE_NULL = UUID.fromString("ec7178ec-e5e1-4432-a3f4-4657e6795210");
    private static final UUID MISOUND = UUID.fromString("5b8e36a5-144a-4c38-b1d7-0002a5d5c51b");
    private static final long OPEN_MS = 3000; // MiSound's own default arrives this soon after its screen opens
    private static final long SETTLE_MS = 3000; // effect changes this soon after an output change are not the user's
    private static final int PARAM_DS_ON = 5;
    private static final int PRIORITY = -1; // below MiSound (0), so its toggle keeps control
    private static final int MAX_TRIES = 10; // creation retries per trigger (output thread may not exist yet)
    private static final long RETRY_MS = 1000;
    private static final long RECHECK_MS = 10000; // after BOOT_COMPLETED: MiSound's default has run by now
    private static final long RECHECK2_MS = 30000; // late DMS / slow first unlock
    // DsTuning ports (com.dolby.dax.DsTuning)
    private static final int PORT_SPEAKER = 0, PORT_HEADPHONE = 3, PORT_BLUETOOTH = 4, PORT_USB = 5;

    private final Context ctx;
    private final AudioManager am;
    private final Handler handler;
    private AudioEffect fx;
    private AudioEffect mi; // MiSound effect holder
    private Constructor<AudioEffect> ctor;
    private Method setParam, getParam;
    private int tries;
    private int tunedPort = -1;
    private String tunedId = "";
    private SharedPreferences effects;
    private String device = "";
    private long outputChangedAt;
    private boolean userChoice; // the user picked an effect in MiSound since this process started
    private final Runnable ensureTask = this::ensure; // one instance: removeCallbacks(this::ensure) never matched

    DolbyKeeper(Context ctx) {
        this.ctx = ctx;
        am = ctx.getSystemService(AudioManager.class);
        HandlerThread t = new HandlerThread("dolby-keeper");
        t.start();
        handler = new Handler(t.getLooper());
    }

    void start() {
        // device-protected storage: the helper is direct-boot aware and starts before the first unlock
        effects = ctx.createDeviceProtectedStorageContext()
                .getSharedPreferences("dolby_effect_per_device", Context.MODE_PRIVATE);
        ctx.getContentResolver().registerContentObserver(Settings.Global.getUriFor("effect_implementer"), false,
                new ContentObserver(handler) {
                    @Override
                    public void onChange(boolean self) {
                        recordEffect();
                    }
                });
        handler.post(this::onOutputChanged);
        IntentFilter f = new IntentFilter(Intent.ACTION_SCREEN_ON);
        f.addAction(Intent.ACTION_BOOT_COMPLETED);
        f.addAction("android.media.VOLUME_CHANGED_ACTION");
        ctx.registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                if (Intent.ACTION_SCREEN_ON.equals(i.getAction())) {
                    trigger();
                } else if (Intent.ACTION_BOOT_COMPLETED.equals(i.getAction())) {
                    scheduleRecheck();
                } else if (i.getIntExtra("android.media.EXTRA_VOLUME_STREAM_TYPE", -1) == AudioManager.STREAM_MUSIC) {
                    handler.post(DolbyKeeper.this::updateTuning);
                }
            }
        }, f, null, handler);
        am.registerAudioDeviceCallback(new AudioDeviceCallback() {
            @Override
            public void onAudioDevicesAdded(AudioDeviceInfo[] d) {
                onOutputChanged();
                trigger();
            }

            @Override
            public void onAudioDevicesRemoved(AudioDeviceInfo[] d) {
                onOutputChanged();
                trigger();
            }
        }, handler);
        am.registerAudioPlaybackCallback(new AudioManager.AudioPlaybackCallback() {
            @Override
            public void onPlaybackConfigChanged(List<AudioPlaybackConfiguration> configs) {
                trigger();
            }
        }, handler);
        trigger();
        if ("1".equals(prop("sys.boot_completed"))) scheduleRecheck(); // process restarted after boot
    }

    private void trigger() {
        handler.removeCallbacks(ensureTask);
        tries = 0;
        handler.post(ensureTask);
    }

    /** BUGS 102: two one-shot re-checks after boot (see class comment). */
    private void scheduleRecheck() {
        handler.removeCallbacks(recheckTask);
        handler.postDelayed(recheckTask, RECHECK_MS);
        handler.postDelayed(recheckTask, RECHECK2_MS);
    }

    private final Runnable recheckTask = this::recheck;

    /** Apply the remembered effect again when the effects do not match it. Cheap when they do (two reads). */
    private void recheck() {
        if (userChoice || device.isEmpty()) return;
        String want = effects.getString(device, "dolby");
        boolean wantDs = "dolby".equals(want);
        boolean ok = fx != null; // reads below throw IllegalStateException when the handle is dead
        try {
            ok = ok && (readDsOn() > 0) == wantDs && fx.getEnabled() == wantDs
                    && (mi == null || mi.getEnabled() == "misound".equals(want))
                    && want.equals(Settings.Global.getString(ctx.getContentResolver(), "effect_implementer"));
        } catch (IllegalStateException e) {
            ok = false;
        }
        Log.i(TAG, "boot re-check on " + device + ": want " + want + ", " + (ok ? "ok" : "mismatch, applying again"));
        if (ok) return;
        trigger(); // new handle if the old one is dead
        applyEffect(want);
    }

    private void ensure() {
        if (fx != null && readDsOn() < 0) {
            Log.i(TAG, "effect handle dead, recreating");
            release();
        }
        if (fx == null) {
            if (!create()) {
                if (++tries < MAX_TRIES) {
                    handler.postDelayed(ensureTask, RETRY_MS);
                } else {
                    Log.w(TAG, "DAP create failed " + MAX_TRIES + " times; next try on the next event");
                }
                return;
            }
            tunedPort = -1; // new chain: select the tuning again
        }
        if (mi == null) mi = holder(MISOUND, "MiSound");
        apply();
        updateTuning();
    }

    private boolean reflect() {
        if (ctor != null) return true;
        try {
            ctor = AudioEffect.class.getConstructor(UUID.class, UUID.class, int.class, int.class);
            setParam = AudioEffect.class.getMethod("setParameter", int.class, byte[].class);
            getParam = AudioEffect.class.getMethod("getParameter", int.class, byte[].class);
            return true;
        } catch (ReflectiveOperationException e) {
            Log.e(TAG, "AudioEffect hidden API missing: " + e);
            return false;
        }
    }

    private boolean create() {
        if (!reflect()) return false;
        try {
            fx = ctor.newInstance(TYPE_NULL, DAP, PRIORITY, 0);
            fx.setControlStatusListener((effect, control) -> {
                if (control) handler.post(this::apply);
            });
            if (mi != null) {
                try { mi.release(); } catch (RuntimeException ignored) { }
                mi = null;
            }
            mi = holder(MISOUND, "MiSound");
            Log.i(TAG, "DAP created on session 0, control " + fx.hasControl());
            return true;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            Log.w(TAG, "DAP create failed: " + cause);
            fx = null;
            return false;
        }
    }

    /** Long-lived low-priority handle for an effect on session 0, or null. */
    private AudioEffect holder(UUID uuid, String name) {
        if (!reflect()) return null;
        try {
            AudioEffect e = ctor.newInstance(TYPE_NULL, uuid, PRIORITY, 0);
            e.setControlStatusListener((effect, control) -> {
                if (control) handler.post(this::apply);
            });
            return e;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, name + " holder failed: " + (e.getCause() != null ? e.getCause() : e));
            return null;
        }
    }

    /** Make the effects' enabled states match the saved DS state and effect_implementer, when we hold control. */
    private void apply() {
        if (mi != null) {
            try {
                boolean wantMi = "misound".equals(Settings.Global.getString(ctx.getContentResolver(), "effect_implementer"));
                if (mi.hasControl() && mi.getEnabled() != wantMi) {
                    mi.setEnabled(wantMi);
                    Log.i(TAG, "MiSound effect " + (wantMi ? "on" : "off"));
                }
            } catch (IllegalStateException e) {
                Log.w(TAG, "MiSound apply failed: " + e);
            }
        }
        if (fx == null || !fx.hasControl()) return;
        int on = readDsOn();
        if (on < 0) return;
        boolean want = on > 0;
        try {
            if (fx.getEnabled() != want) {
                setDsOn(want);
                fx.setEnabled(want);
                Log.i(TAG, "applied saved state: " + (want ? "on" : "off"));
            }
        } catch (IllegalStateException e) {
            Log.w(TAG, "apply failed: " + e);
        }
    }

    /** Output port as DsTuning numbers (newest-priority order like stock: BT, USB, wired, speaker). */
    private int currentPort() {
        int port = PORT_SPEAKER;
        for (AudioDeviceInfo d : am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            switch (d.getType()) {
                case AudioDeviceInfo.TYPE_BLUETOOTH_A2DP:
                case AudioDeviceInfo.TYPE_BLE_HEADSET:
                case AudioDeviceInfo.TYPE_BLE_SPEAKER:
                    port = PORT_BLUETOOTH;
                    break;
                case AudioDeviceInfo.TYPE_USB_HEADSET:
                case AudioDeviceInfo.TYPE_USB_DEVICE:
                    if (port == PORT_SPEAKER || port == PORT_HEADPHONE) port = PORT_USB;
                    break;
                case AudioDeviceInfo.TYPE_WIRED_HEADSET:
                case AudioDeviceInfo.TYPE_WIRED_HEADPHONES:
                    if (port == PORT_SPEAKER) port = PORT_HEADPHONE;
                    break;
                default:
                    break;
            }
        }
        return port;
    }

    private static String deviceClass(int port) {
        switch (port) {
            case PORT_BLUETOOTH: return "bluetooth_device";
            case PORT_USB: return "usb_device";
            case PORT_HEADPHONE: return "wiredHeadset_device";
            default: return "speaker";
        }
    }

    /** effect_implementer changed: the user's choice in MiSound is remembered for the current device (stock
     *  saveEffectForDevice); a change by MiSound's background presenter (boot / device defaults) is undone. */
    private void recordEffect() {
        String e = Settings.Global.getString(ctx.getContentResolver(), "effect_implementer");
        if (e == null || device.isEmpty()) return;
        String want = effects.getString(device, "dolby");
        if (e.equals(want)) return; // our own write, or nothing new
        boolean settled = SystemClock.elapsedRealtime() - outputChangedAt > SETTLE_MS;
        if (settled && miSoundForeground() && !miSoundJustOpened()) {
            userChoice = true;
            effects.edit().putString(device, e).apply();
            Log.i(TAG, "effect for " + device + ": " + e);
            handler.post(this::apply); // MiSound switched both effects itself; the holders follow
        } else {
            Log.i(TAG, "automatic change to " + e + " on " + device + ", back to " + want);
            applyEffect(want);
        }
    }

    /** Output changed: apply the effect remembered for the new device (stock onDeviceChanged). */
    private void onOutputChanged() {
        String dev = deviceClass(currentPort());
        if (dev.equals(device)) return;
        device = dev;
        outputChangedAt = SystemClock.elapsedRealtime();
        try {
            Settings.Global.putString(ctx.getContentResolver(), "last_device", dev);
        } catch (SecurityException e) {
            Log.w(TAG, "last_device: " + e);
        }
        String want = effects.getString(dev, "dolby");
        Log.i(TAG, "device " + dev + ": " + want);
        applyEffect(want);
    }

    /** Stock BaseEffectPresenter setDolbyActive / setMiSoundActive / setEffectDeactivate. */
    private void applyEffect(String want) {
        try {
            if (!want.equals(Settings.Global.getString(ctx.getContentResolver(), "effect_implementer"))) {
                Settings.Global.putString(ctx.getContentResolver(), "effect_implementer", want);
            }
        } catch (SecurityException e) {
            Log.w(TAG, "effect_implementer: " + e);
        }
        boolean misound = "misound".equals(want);
        setEnabledTemp(MISOUND, misound, -1);
        setDsOnTemp("dolby".equals(want));
    }

    /** BUGS 108: did MiSound's screen open less than OPEN_MS ago (its cold-start default, not a tap)? */
    private boolean miSoundJustOpened() {
        try {
            UsageStatsManager u = ctx.getSystemService(UsageStatsManager.class);
            long now = System.currentTimeMillis();
            UsageEvents ev = u.queryEvents(now - 15000, now);
            UsageEvents.Event e = new UsageEvents.Event();
            long last = 0;
            while (ev.getNextEvent(e)) {
                if ("com.miui.misound".equals(e.getPackageName())
                        && e.getEventType() == UsageEvents.Event.ACTIVITY_RESUMED) {
                    last = Math.max(last, e.getTimeStamp());
                }
            }
            return last > 0 && now - last < OPEN_MS;
        } catch (RuntimeException e) {
            Log.w(TAG, "MiSound usage events: " + e);
            return false;
        }
    }

    /** Is MiSound's UI in the foreground (the only place the user picks an effect)? */
    private boolean miSoundForeground() {
        try {
            ActivityManager a = ctx.getSystemService(ActivityManager.class);
            int imp = (Integer) ActivityManager.class.getMethod("getPackageImportance", String.class)
                    .invoke(a, "com.miui.misound");
            return imp <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, "MiSound importance: " + (e.getCause() != null ? e.getCause() : e));
            return true; // unknown: trust the change (1.5 behaviour)
        }
    }

    /** Set DS on/off through a temporary priority 0 handle (works while MiSound holds control); the holder's apply()
     *  then matches the enabled state when it gets control back. */
    private void setDsOnTemp(boolean on) {
        setEnabledTemp(DAP, on, on ? 1 : 0);
    }

    /** Enable/disable an effect through a temporary priority 0 handle; ds >= 0 also sets Dolby's DS param. */
    private void setEnabledTemp(UUID uuid, boolean on, int ds) {
        if (!reflect()) return;
        AudioEffect t = null;
        try {
            t = ctor.newInstance(TYPE_NULL, uuid, 0, 0);
            if (ds >= 0) {
                byte[] value = new byte[12];
                System.arraycopy(le(1), 0, value, 4, 4);
                System.arraycopy(le(ds), 0, value, 8, 4);
                Object r = setParam.invoke(t, PARAM_DS_ON, value);
                if (!Integer.valueOf(AudioEffect.SUCCESS).equals(r)) {
                    Log.w(TAG, "DS " + ds + " not accepted (" + r + "): DMS/DAP not ready? boot re-check will retry");
                }
            }
            t.setEnabled(on);
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, uuid + " " + on + " failed: " + (e.getCause() != null ? e.getCause() : e));
        } finally {
            if (t != null) t.release();
        }
        handler.post(this::apply);
    }

    /** Stock DolbyEffectController.updateDolbyTunning(), non-spatializer path. */
    private void updateTuning() {
        if (!"true".equals(prop("vendor.audio.dolby.control.support")) || !reflect()) return;
        int port = currentPort();
        String id;
        switch (port) {
            case PORT_HEADPHONE: id = "default_headphone"; break;
            case PORT_BLUETOOTH: id = "default_bluetooth"; break;
            case PORT_USB: id = "default_usb"; break;
            default:
                if ("true".equals(prop("vendor.audio.dolby.control.tunning.by.volume.support"))) {
                    int threshold = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) * 10 / 15;
                    id = am.getStreamVolume(AudioManager.STREAM_MUSIC) > threshold
                            ? "speaker_volume_high" : "speaker_volume_low";
                } else {
                    id = "default_internal_speaker";
                }
        }
        if (port == tunedPort && id.equals(tunedId)) return;
        AudioEffect t = null;
        try {
            t = ctor.newInstance(TYPE_NULL, DAP, 0, 0);
            if (!t.hasControl()) {
                Log.i(TAG, "tuning: no control, " + port + " " + id + " later");
                return;
            }
            byte[] name = id.getBytes(StandardCharsets.US_ASCII);
            byte[] v = new byte[4 + name.length];
            System.arraycopy(le(port), 0, v, 0, 4);
            System.arraycopy(name, 0, v, 4, name.length);
            int r = (Integer) setParam.invoke(t, 4, v);
            if (r == AudioEffect.SUCCESS) {
                tunedPort = port;
                tunedId = id;
                Log.i(TAG, "tuning: port " + port + " " + id);
            } else {
                Log.w(TAG, "tuning " + id + " = " + r);
            }
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.w(TAG, "tuning failed: " + (e.getCause() != null ? e.getCause() : e));
        } finally {
            if (t != null) t.release();
        }
    }

    private int readDsOn() {
        byte[] value = new byte[12];
        try {
            int r = (Integer) getParam.invoke(fx, PARAM_DS_ON, value);
            if (r < 0) return -1;
        } catch (ReflectiveOperationException | IllegalStateException e) {
            return -1;
        }
        return (value[0] & 0xff) | (value[1] & 0xff) << 8 | (value[2] & 0xff) << 16
                | (value[3] & 0xff) << 24;
    }

    private void setDsOn(boolean on) {
        byte[] value = new byte[12];
        System.arraycopy(le(0), 0, value, 0, 4);
        System.arraycopy(le(1), 0, value, 4, 4);
        System.arraycopy(le(on ? 1 : 0), 0, value, 8, 4);
        try {
            int r = (Integer) setParam.invoke(fx, PARAM_DS_ON, value);
            if (r != AudioEffect.SUCCESS) Log.w(TAG, "setDsOn(" + on + ") = " + r);
        } catch (ReflectiveOperationException e) {
            Log.w(TAG, "setDsOn failed: " + e.getCause());
        }
    }

    private void release() {
        try {
            fx.release();
        } catch (RuntimeException ignored) {
        }
        fx = null;
        if (mi != null) {
            try {
                mi.release();
            } catch (RuntimeException ignored) {
            }
            mi = null;
        }
    }

    private static String prop(String key) {
        try {
            return (String) Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class).invoke(null, key);
        } catch (ReflectiveOperationException e) {
            return "";
        }
    }

    private static byte[] le(int v) {
        return new byte[] {(byte) v, (byte) (v >> 8), (byte) (v >> 16), (byte) (v >> 24)};
    }
}
