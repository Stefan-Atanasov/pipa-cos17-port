import android.graphics.Bitmap;
import android.media.MediaMetadataRetriever;

// BUGS-TODO 33: ask mediaserver for one video frame, like a thumbnail does.
// Run: CLASSPATH=/data/local/tmp/framecap.dex app_process / FrameTest <file> [usec]
public class FrameTest {
    public static void main(String[] args) throws Exception {
        long t = args.length > 1 ? Long.parseLong(args[1]) : 1000000L;
        MediaMetadataRetriever r = new MediaMetadataRetriever();
        r.setDataSource(args[0]);
        System.out.println("mime=" + r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                + " size=" + r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                + "x" + r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                + " transfer=" + r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER)
                + " standard=" + r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_COLOR_STANDARD));
        Bitmap b = r.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
        System.out.println(b == null ? "frame=null" : "frame=" + b.getWidth() + "x" + b.getHeight() + " " + b.getConfig());
        r.release();
    }
}
