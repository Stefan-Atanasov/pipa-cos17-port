// Test client for Xiaomi's displayfeature HIDL HAL (ROM layer 2y). Sends
// IDisplayFeature::setFeature(displayId, feature, value, cookie) (transaction 1) over hwbinder.
//
//   CLASSPATH=/data/local/tmp/dfcall.jar app_process / DfCall <feature> <value> [cookie=255] [displayId=0]
//
// Feature IDs (miui DisplayFeatureManager): 0 adaptive, 1 enhance (vivid), 2 standard, 3 eye care (reading),
// 19 game HDR, 26 expert (cookie = parameter), 31 paper colour, 32 TrueTone. For 0/1/2 the value is the
// colour-temperature level. Hidden APIs through reflection: app_process has no hidden-API enforcement.
public class DfCall {
    static final String IFACE = "vendor.xiaomi.hardware.displayfeature@1.0::IDisplayFeature";

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: DfCall <feature> <value> [cookie=255] [displayId=0]");
            System.exit(2);
        }
        int feature = Integer.parseInt(args[0]);
        int value = Integer.parseInt(args[1]);
        int cookie = args.length > 2 ? Integer.parseInt(args[2]) : 255;
        int display = args.length > 3 ? Integer.parseInt(args[3]) : 0;

        Class<?> hwBinder = Class.forName("android.os.HwBinder");
        Class<?> iHwBinder = Class.forName("android.os.IHwBinder");
        Class<?> hwParcel = Class.forName("android.os.HwParcel");
        Object binder = hwBinder.getMethod("getService", String.class, String.class).invoke(null, IFACE, "default");
        if (binder == null) {
            System.err.println("no " + IFACE + "/default");
            System.exit(1);
        }
        Object req = hwParcel.getConstructor().newInstance();
        hwParcel.getMethod("writeInterfaceToken", String.class).invoke(req, IFACE);
        for (int v : new int[] {display, feature, value, cookie}) {
            hwParcel.getMethod("writeInt32", int.class).invoke(req, v);
        }
        Object reply = hwParcel.getConstructor().newInstance();
        iHwBinder.getMethod("transact", int.class, hwParcel, hwParcel, int.class).invoke(binder, 1, req, reply, 0);
        hwParcel.getMethod("verifySuccess").invoke(reply);
        hwParcel.getMethod("releaseTemporaryStorage").invoke(req);
        System.out.println("setFeature(display=" + display + ", feature=" + feature + ", value=" + value
                + ", cookie=" + cookie + "): ok");
    }
}
