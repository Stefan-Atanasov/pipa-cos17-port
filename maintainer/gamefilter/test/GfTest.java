import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;

/** Sends Game Filter modes like OplusGames (oplus_vrr_service transaction 67), holds the token, then exits.
 *  CLASSPATH=/data/local/tmp/gftest.dex app_process / GfTest <hold seconds> <mode>... */
public class GfTest {
    public static void main(String[] a) throws Exception {
        IBinder vrr = (IBinder) Class.forName("android.os.ServiceManager").getMethod("getService", String.class)
                .invoke(null, "oplus_vrr_service");
        IBinder token = new Binder();
        for (int i = 1; i < a.length; i++) {
            Parcel d = Parcel.obtain(), r = Parcel.obtain();
            d.writeInterfaceToken("com.oplus.vrr.IOPlusRefreshRate");
            d.writeInt(Integer.parseInt(a[i]));
            d.writeStrongBinder(token);
            vrr.transact(67, d, r, 0);
            System.out.println("mode " + a[i] + " sent");
            d.recycle(); r.recycle();
        }
        Thread.sleep(Integer.parseInt(a[0]) * 1000L);
    }
}
