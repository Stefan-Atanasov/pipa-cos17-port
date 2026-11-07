import android.media.audiofx.AudioEffect;
import java.lang.reflect.*;
import java.util.UUID;
/** Ctl ds=0|1 prof=N tune=port:name get : Dolby DAP control on session 0 the way MiSound/DolbyEffectController do. */
public class Ctl {
    static Method set, get; static AudioEffect fx;
    static byte[] le(int... v) { byte[] b = new byte[v.length * 4]; for (int i = 0; i < v.length; i++) for (int k = 0; k < 4; k++) b[i*4+k] = (byte)(v[i] >> (8*k)); return b; }
    static int rd(byte[] b, int o) { return (b[o]&0xff)|(b[o+1]&0xff)<<8|(b[o+2]&0xff)<<16|(b[o+3]&0xff)<<24; }
    static int getI(int id) throws Exception { byte[] b = new byte[12]; System.arraycopy(le(id),0,b,0,4); get.invoke(fx, id + 5, b); return rd(b, 0); }
    public static void main(String[] a) throws Exception {
        Constructor<AudioEffect> c = AudioEffect.class.getConstructor(UUID.class, UUID.class, int.class, int.class);
        set = AudioEffect.class.getMethod("setParameter", int.class, byte[].class);
        get = AudioEffect.class.getMethod("getParameter", int.class, byte[].class);
        fx = c.newInstance(UUID.fromString("ec7178ec-e5e1-4432-a3f4-4657e6795210"), UUID.fromString("9d4921da-8225-4f29-aefa-39537a04bcaa"), 1, 0);
        for (String s : a) {
            String[] kv = s.split("=", 2); int r = 0;
            if (kv[0].equals("ds")) { int v = Integer.parseInt(kv[1]); r = (Integer) set.invoke(fx, 5, le(0, 1, v)); fx.setEnabled(v != 0); }
            else if (kv[0].equals("prof")) r = (Integer) set.invoke(fx, 5, le(0x0a000000, 1, Integer.parseInt(kv[1])));
            else if (kv[0].equals("tune")) { String[] p = kv[1].split(":", 2); byte[] id = p[1].getBytes(); byte[] b = new byte[id.length + 4];
                System.arraycopy(le(Integer.parseInt(p[0])), 0, b, 0, 4); System.arraycopy(id, 0, b, 4, id.length); r = (Integer) set.invoke(fx, 4, b); }
            else if (kv[0].equals("geq")) { // geq=d1,..,d20 in dB (profile 0), sent like MiSound: [0x1000000, n+1, profile, 110, gains*16]
                String[] g = kv[1].split(","); int[] v = new int[4 + g.length]; v[0] = 0x1000000; v[1] = g.length + 1; v[2] = 0; v[3] = 110;
                for (int i = 0; i < g.length; i++) v[4 + i] = Math.round(Float.parseFloat(g[i]) * 16);
                r = (Integer) set.invoke(fx, 5, le(v));
                int r2 = (Integer) set.invoke(fx, 5, le(0x1000000, 2, 0, 106, 1)); System.out.println("geon -> " + r2); }
            else if (kv[0].equals("get")) { System.out.println("ds " + getI(0) + " prof " + getI(0x0a000000) + " enabled " + fx.getEnabled()); continue; }
            System.out.println(s + " -> " + r);
        }
        fx.release(); System.exit(0);
    }
}
