package com.port.pipa.helper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * helper 2.5 (BUGS 153): pen button actions that need an app API. pen_keys.sh (pipa_port, root) sends
 * `am broadcast -n com.port.pipa.helper/.PenActionReceiver -a com.port.pipa.helper.TORCH`. The flashlight has no
 * shell command; CameraManager.setTorchMode needs no permission. The torch state comes from a TorchCallback that
 * HelperApp registers at start (the helper is persistent).
 */
public final class PenActionReceiver extends BroadcastReceiver {
    static final String TORCH = "com.port.pipa.helper.TORCH";
    private static final String TAG = "PipaPenAction";
    private static String torchId;
    private static boolean torchOn;

    static void init(Context c) {
        CameraManager cm = c.getSystemService(CameraManager.class);
        try {
            for (String id : cm.getCameraIdList()) {
                CameraCharacteristics ch = cm.getCameraCharacteristics(id);
                Boolean flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                Integer facing = ch.get(CameraCharacteristics.LENS_FACING);
                if (Boolean.TRUE.equals(flash) && facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    torchId = id;
                    break;
                }
            }
            cm.registerTorchCallback(new CameraManager.TorchCallback() {
                @Override public void onTorchModeChanged(String id, boolean on) {
                    if (id.equals(torchId)) torchOn = on;
                }
            }, new Handler(Looper.getMainLooper()));
        } catch (Exception e) {
            Log.w(TAG, "torch init: " + e);
        }
    }

    @Override
    public void onReceive(Context c, Intent i) {
        if (!TORCH.equals(i.getAction()) || torchId == null) return;
        try {
            c.getSystemService(CameraManager.class).setTorchMode(torchId, !torchOn);
        } catch (Exception e) {
            Log.w(TAG, "torch: " + e);
        }
    }
}
