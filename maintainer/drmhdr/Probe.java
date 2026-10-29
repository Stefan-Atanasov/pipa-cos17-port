import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaDrm;
import java.util.UUID;

/** DRM / HDR probe (BUGS-TODO 28, 29): CLASSPATH=/data/local/tmp/probe.dex app_process / Probe */
public class Probe {
    static final UUID WV = new UUID(0xEDEF8BA979D64ACEL, 0xA3C827DCD51D21EDL);
    public static void main(String[] a) {
        try {
            MediaDrm d = new MediaDrm(WV);
            for (String k : new String[] {"vendor", "version", "securityLevel", "systemId", "hdcpLevel", "maxHdcpLevel",
                    "oemCryptoApiVersion", "provisioningUniqueId"}) {
                try { System.out.println("widevine " + k + " = " + (k.equals("provisioningUniqueId") ? d.getPropertyByteArray(k).length + " bytes" : d.getPropertyString(k))); }
                catch (Throwable t) { System.out.println("widevine " + k + " : " + t); }
            }
            d.close();
        } catch (Throwable t) { System.out.println("widevine: " + t); }
        for (MediaCodecInfo ci : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (ci.isEncoder()) continue;
            for (String type : ci.getSupportedTypes()) {
                if (!type.startsWith("video/")) continue;
                StringBuilder sb = new StringBuilder();
                try {
                    for (MediaCodecInfo.CodecProfileLevel pl : ci.getCapabilitiesForType(type).profileLevels) {
                        int p = pl.profile;
                        boolean hdr = (type.contains("hevc") && (p == 0x1000 || p == 0x2000 || p == 4096)) || (type.contains("vp9") && p >= 0x1000)
                                || (type.contains("av01") && p >= 0x1000) || type.contains("dolby");
                        if (hdr) sb.append(" 0x").append(Integer.toHexString(p));
                    }
                } catch (Throwable t) { sb.append(" ?"); }
                if (sb.length() > 0 || type.contains("dolby")) System.out.println("codec " + ci.getName() + " " + type + " hdrProfiles:" + sb);
            }
        }
    }
}
