package com.android.server.display.color.feature;

import android.util.Slog;

import com.android.server.LocalServices;
import com.android.server.display.color.DisplayTransformManager;

/**
 * pipa port (BUGS-TODO 64): Game Eye Care (Games app, "game dark eye protect") as a SurfaceFlinger colour matrix.
 *
 * OPPO devices apply it in the panel: OplusFeatureGameEyeCare.updateGameEyeCareStatus() sends
 * IDisplayPanelFeature id 228 (0xe4) = 1 while the switch is on and a game is in full screen. pipa has no panel
 * feature (the 4r shim only stores the value), so nothing changed. updateGameEyeCareStatus() also calls set() here:
 * the effect becomes one level of the DisplayTransformManager colour matrix, so it stacks with Eye Comfort, Night
 * Light, Game Filter (151) and grayscale.
 *
 * Effect: warmer and a little darker (less blue light in dark game scenes). Linear-light gains.
 */
public final class PipaGameEyeCare {
    private static final String TAG = "PipaGameEyeCare";
    /** After Game Filter (151), before GRAYSCALE (200) and INVERT (300). */
    private static final int LEVEL = 152;
    private static final float R = 0.94f, G = 0.86f, B = 0.70f;

    private static int sStatus = -1;

    private PipaGameEyeCare() {}

    public static void set(int status) {
        try {
            synchronized (PipaGameEyeCare.class) {
                if (status == sStatus) return;
                sStatus = status;
            }
            DisplayTransformManager dtm = LocalServices.getService(DisplayTransformManager.class);
            if (dtm == null) return;
            float[] m = status == 1
                    ? new float[] {R, 0, 0, 0, 0, G, 0, 0, 0, 0, B, 0, 0, 0, 0, 1}   // column-major 4x4
                    : null;
            dtm.setColorMatrix(LEVEL, m);
            Slog.i(TAG, "status " + status);
        } catch (Throwable t) {
            Slog.e(TAG, "status " + status, t);
        }
    }
}
