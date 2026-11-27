package com.port.pipa.helper;

import android.content.Context;
import android.hardware.input.InputManager;
import android.os.Build;
import android.provider.Settings;
import android.view.InputDevice;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

/** helper 2.5: what the Pipa Helper app shows as status. All reads are cheap; nothing here polls. */
final class Status {
    private Status() { }

    /** the port build (step 8e writes the build tag, e.g. "pt133") */
    static String build() {
        String b = firstLine("/system_ext/pipa_port/build");
        return b == null ? "" : b;
    }

    // No kernel version here: apps may get a spoofed uname (susfs), and the app must not reveal the real one.

    static String rom() { return Build.DISPLAY; }

    /** a system property (hidden android.os.SystemProperties.get by reflection, as DolbyKeeper); "" if unreadable */
    static String prop(String key) {
        try {
            Object v = Class.forName("android.os.SystemProperties").getMethod("get", String.class).invoke(null, key);
            return v == null ? "" : (String) v;
        } catch (ReflectiveOperationException e) {
            return "";
        }
    }

    /** the Xiaomi pen is connected over Bluetooth (pipa_port sets the OPPO pencil state, BUGS 153) */
    static boolean penConnected(Context c) {
        return Settings.Global.getInt(c.getContentResolver(), "ipe_pencil_connect_state", 0) == 2;
    }

    /** pen battery in %, or -1 */
    static int penBattery(Context c) {
        return Settings.Global.getInt(c.getContentResolver(), "ipe_pencil_battery_level", -1);
    }

    /** the keyboard case (or another hardware keyboard) is attached */
    static boolean keyboard(Context c) {
        InputManager im = c.getSystemService(InputManager.class);
        for (int id : im.getInputDeviceIds()) {
            InputDevice d = im.getInputDevice(id);
            if (d != null && !d.isVirtual() && d.isEnabled()
                    && d.getKeyboardType() == InputDevice.KEYBOARD_TYPE_ALPHABETIC) return true;
        }
        return false;
    }

    static boolean global(Context c, String key, int def) {
        return Settings.Global.getInt(c.getContentResolver(), key, def) == 1;
    }

    /** write a Global setting (WRITE_SECURE_SETTINGS, granted in the ROM); false if not allowed */
    static boolean putGlobal(Context c, String key, int v) {
        try {
            return Settings.Global.putInt(c.getContentResolver(), key, v);
        } catch (SecurityException e) {
            return false;
        }
    }

    private static String firstLine(String path) {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String l = r.readLine();
            return l == null ? null : l.trim();
        } catch (IOException | SecurityException e) {
            return null;
        }
    }
}
