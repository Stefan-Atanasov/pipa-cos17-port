package pipa.probe;

import android.app.Activity;
import android.os.Bundle;
import android.view.Display;
import java.io.FileOutputStream;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaDrm;
import java.util.UUID;

/** DRM / HDR probe (BUGS-TODO 28, 29): am start -n pipa.probe/.Main; result in getExternalFilesDir()/probe.txt */
public class Main extends Activity {
    static StringBuilder out = new StringBuilder();
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        new Thread(() -> {
            run();
            Display.HdrCapabilities h = getDisplay().getHdrCapabilities();
            out.append("display hdrTypes = ").append(java.util.Arrays.toString(h.getSupportedHdrTypes()))
               .append(" maxLum=").append(h.getDesiredMaxLuminance()).append("\n");
            out.append("display isHdr = ").append(getDisplay().isHdr()).append(" wideColor=").append(getDisplay().isWideColorGamut()).append("\n");
            try (FileOutputStream o = new FileOutputStream(new java.io.File(getExternalFilesDir(null), "probe.txt"))) { o.write(out.toString().getBytes()); } catch (Exception e) {}
            runOnUiThread(this::finish);
        }).start();
    }
    static final UUID WV = new UUID(0xEDEF8BA979D64ACEL, 0xA3C827DCD51D21EDL);
    static void run() {
        try {
            MediaDrm d = new MediaDrm(WV);
            for (String k : new String[] {"vendor", "version", "securityLevel", "systemId", "hdcpLevel", "maxHdcpLevel",
                    "oemCryptoApiVersion", "provisioningUniqueId"}) {
                try { println("widevine " + k + " = " + (k.equals("provisioningUniqueId") ? d.getPropertyByteArray(k).length + " bytes" : d.getPropertyString(k))); }
                catch (Throwable t) { println("widevine " + k + " : " + t); }
            }
            d.close();
        } catch (Throwable t) { println("widevine: " + t); }
        for (MediaCodecInfo ci : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (ci.isEncoder()) continue;
            for (String type : ci.getSupportedTypes()) {
                if (!type.startsWith("video/")) continue;
                StringBuilder sb = new StringBuilder();
                try {
                    for (MediaCodecInfo.CodecProfileLevel pl : ci.getCapabilitiesForType(type).profileLevels) {
                        int p = pl.profile;
                        boolean hdr = (type.contains("hevc") && (p == 0x1000 || p == 0x2000)) || (type.contains("vp9") && p >= 0x1000)
                                || (type.contains("av01") && p >= 0x1000) || type.contains("dolby");
                        sb.append(hdr ? " HDR:0x" : " 0x").append(Integer.toHexString(p)).append("/L0x").append(Integer.toHexString(pl.level));
                    }
                    sb.append(" colorFormats:");
                    for (int cf : ci.getCapabilitiesForType(type).colorFormats) sb.append(" ").append(cf);
                    sb.append(" hdrEditing=").append(ci.getCapabilitiesForType(type).isFeatureSupported("hdr-editing"));
                } catch (Throwable t) { sb.append(" ?"); }
                if (type.contains("hevc") || type.contains("vp9") || type.contains("av01") || type.contains("dolby")) println("codec " + ci.getName() + " " + type + " hdrProfiles:" + sb);
            }
        }
    }
    static void println(String x) { out.append(x).append("\n"); }
}
