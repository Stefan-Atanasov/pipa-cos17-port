package pipa.touch;

import android.os.*;
import java.lang.reflect.Method;

/** Separate host and registrar, as used by the charger shim. */
public final class TouchHost {
    private static final String LOCAL = "pipa.touch.shim";
    private static Method method(String name, Class<?>... args) throws Exception {
        return Class.forName("android.os.ServiceManager").getMethod(name, args);
    }
    private static IBinder check(String name) throws Exception {
        return (IBinder) method("checkService", String.class).invoke(null, name);
    }
    private static void add(String name, IBinder binder) throws Exception {
        method("addService", String.class, IBinder.class).invoke(null, name, binder);
        IBinder registered = check(name);
        if (registered == null || !TouchService.DESCRIPTOR.equals(registered.getInterfaceDescriptor()))
            throw new IllegalStateException("Registration failed: " + name);
    }
    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("register")) {
            for (int attempt = 0; attempt < 30; attempt++) {
                IBinder existing = check(TouchService.NAME);
                if (existing != null) throw new IllegalStateException("Touch service already exists");
                IBinder proxy = check(LOCAL);
                if (proxy != null) {
                    // Pass a remote BinderProxy to servicemanager, as ShimRegister does.
                    add(TouchService.NAME, proxy);
                    System.out.println("Registered " + TouchService.NAME);
                    return;
                }
                Thread.sleep(1000);
            }
            throw new IllegalStateException("Touch host did not start");
        }
        if (check(LOCAL) != null || check(TouchService.NAME) != null)
            throw new IllegalStateException("Touch service already exists");
        Looper.prepareMainLooper();
        add(LOCAL, new TouchService(args.length > 0 ? args[0] : "/system_ext/pipa_port/xiaomi_touch_ioctl"));
        System.out.println("Touch host ready");
        Looper.loop();
    }
}
