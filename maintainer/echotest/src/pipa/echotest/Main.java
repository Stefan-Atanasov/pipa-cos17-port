package pipa.echotest;

import android.app.Activity;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioRecord;
import android.media.AudioTrack;
import android.media.MediaRecorder;
import android.media.audiofx.AcousticEchoCanceler;
import android.os.Bundle;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Random;

/**
 * Plays a speech-like test signal and records the mic at the same time, with the settings of com.oplus.vdc in a
 * shared call: mode IN_COMMUNICATION, playback usage VOICE_COMMUNICATION, record source VOICE_COMMUNICATION,
 * 16 kHz mono. Output in getExternalFilesDir(): play.raw (the signal), <tag>.raw (the recording), <tag>.txt.
 *
 * am start -W -n pipa.echotest/.Main --es tag vc [--ei mode 3] [--ei src 7] [--ei usage 2] [--ei vol -1]
 *          [--ef amp 0.3] [--ez aec false] [--ez mute false] [--ez spk false]
 *          [--es appname com.tencent.mm]   (sends appname=+<pkg> to the HAL, like HyperOS's audio policy)
 */
public class Main extends Activity {
    static final String T = "pipa.echotest";
    static final int RATE = 16000;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        // a recording app that is not in the foreground gets silence: keep the screen on during the test
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        Intent in = getIntent();
        new Thread(() -> {
            try {
                run(in);
            } catch (Throwable t) {
                Log.e(T, "test failed", t);
                write(in, "status=failed " + t + "\n");
            } finally {
                runOnUiThread(this::finish);
            }
        }, "echotest").start();
    }

    /** 1 s silence, 6 s band-limited noise in syllable bursts (300-3400 Hz), 1 s silence. Seed 1: the same each run. */
    static short[] signal(float amp) {
        short[] s = new short[RATE * 8];
        Random r = new Random(1);
        double lp = 0, hp = 0, env = 0;
        int n = RATE, end = RATE * 7;
        while (n < end) {
            int on = RATE * (150 + r.nextInt(250)) / 1000, off = RATE * (50 + r.nextInt(150)) / 1000;
            for (int i = 0; i < on + off && n < end; i++, n++) {
                double x = r.nextGaussian();
                lp += 0.73 * (x - lp);          // low-pass ~3.4 kHz
                hp += 0.11 * (lp - hp);         // high-pass ~300 Hz: lp - hp
                env += ((i < on ? 1.0 : 0.0) - env) * 0.004;
                s[n] = (short) Math.max(-32767, Math.min(32767, (lp - hp) * env * amp * 32767 * 0.9));
            }
        }
        return s;
    }

    void run(Intent in) throws Exception {
        String tag = in.getStringExtra("tag") == null ? "run" : in.getStringExtra("tag");
        int mode = in.getIntExtra("mode", AudioManager.MODE_IN_COMMUNICATION);
        int src = in.getIntExtra("src", MediaRecorder.AudioSource.VOICE_COMMUNICATION);
        int usage = in.getIntExtra("usage", AudioAttributes.USAGE_VOICE_COMMUNICATION);
        int vol = in.getIntExtra("vol", -1);
        float amp = in.getFloatExtra("amp", 0.3f);
        boolean aec = in.getBooleanExtra("aec", false), mute = in.getBooleanExtra("mute", false);
        boolean spk = in.getBooleanExtra("spk", false);
        String appname = in.getStringExtra("appname");
        AudioManager am = getSystemService(AudioManager.class);
        int stream = AudioManager.STREAM_VOICE_CALL, oldVol;
        short[] sig = signal(amp);
        save(new File(getExternalFilesDir(null), "play.raw"), sig, sig.length);

        am.setMode(mode);
        if (spk) {   // speakerphone route, like the speaker button in the call screen
            for (AudioDeviceInfo d : am.getAvailableCommunicationDevices()) {
                if (d.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) am.setCommunicationDevice(d);
            }
        }
        Thread.sleep(300);   // the call volume is per device: set it after the route
        oldVol = am.getStreamVolume(stream);
        if (vol >= 0) am.setStreamVolume(stream, vol, 0);
        int minRec = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        AudioRecord rec = new AudioRecord.Builder().setAudioSource(src)
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(RATE).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(Math.max(minRec * 4, 640 * 2 * 4)).build();
        AcousticEchoCanceler fx = null;
        if (aec && AcousticEchoCanceler.isAvailable()) {
            fx = AcousticEchoCanceler.create(rec.getAudioSessionId());
            if (fx != null) fx.setEnabled(true);
        }
        AudioTrack trk = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(usage)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setTransferMode(AudioTrack.MODE_STREAM).build();
        if (mute) am.setMicrophoneMute(true);
        if (appname != null) am.setParameters("appname=+" + appname);

        short[] buf = new short[RATE * 11];
        int[] got = {0};
        rec.startRecording();
        Thread reader = new Thread(() -> {
            while (got[0] < buf.length) {
                int n = rec.read(buf, got[0], Math.min(320, buf.length - got[0]));
                if (n <= 0) break;
                got[0] += n;
            }
        });
        reader.start();
        Thread.sleep(500);
        trk.play();
        trk.write(sig, 0, sig.length);   // blocking: returns when the last part is queued
        Thread.sleep(500);
        AudioDeviceInfo outDev = trk.getRoutedDevice(), inDev = rec.getRoutedDevice();
        int curMode = am.getMode(), curVol = am.getStreamVolume(stream);
        boolean muted = am.isMicrophoneMute();
        trk.stop();
        reader.join(5000);
        rec.stop();
        if (mute) am.setMicrophoneMute(false);
        if (appname != null) am.setParameters("appname=-" + appname);
        if (fx != null) fx.release();
        trk.release();
        rec.release();
        if (vol >= 0) am.setStreamVolume(stream, oldVol, 0);
        if (spk) am.clearCommunicationDevice();
        am.setMode(AudioManager.MODE_NORMAL);

        save(new File(getExternalFilesDir(null), tag + ".raw"), buf, got[0]);
        write(in, "status=ok\nmode=" + curMode + "\nsrc=" + src + "\nusage=" + usage + "\nvol=" + curVol
                + "\namp=" + amp + "\nspk=" + spk + "\nappname=" + appname + "\naec_explicit=" + (fx != null) + "\nmic_muted=" + muted
                + "\nout=" + dev(outDev) + "\nin=" + dev(inDev) + "\nsamples=" + got[0] + "\n");
        Log.i(T, "done " + tag);
    }

    static String dev(AudioDeviceInfo d) {
        return d == null ? "null" : d.getType() + "/" + d.getProductName();
    }

    static void save(File f, short[] s, int n) throws IOException {
        ByteBuffer bb = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN);
        for (int i = 0; i < n; i++) bb.putShort(s[i]);
        try (FileOutputStream o = new FileOutputStream(f)) {
            o.write(bb.array());
        }
    }

    void write(Intent in, String text) {
        String tag = in.getStringExtra("tag") == null ? "run" : in.getStringExtra("tag");
        try (FileOutputStream o = new FileOutputStream(new File(getExternalFilesDir(null), tag + ".txt"))) {
            o.write(text.getBytes());
        } catch (IOException e) {
            Log.e(T, "status write", e);
        }
    }
}
