import android.media.*;
import java.io.*;
/** Plays a 16-bit stereo 48 kHz WAV (44-byte header) as media/music through the normal mixer (global Dolby applies). */
public class Play {
    public static void main(String[] a) throws Exception {
        byte[] d; try (FileInputStream f = new FileInputStream(a[0])) { d = f.readAllBytes(); }
        AudioTrack t = new AudioTrack.Builder()
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(new AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(48000 * 4).build();
        t.play(); t.write(d, 44, d.length - 44); 
        Thread.sleep(500); t.stop(); t.release(); System.exit(0);
    }
}
