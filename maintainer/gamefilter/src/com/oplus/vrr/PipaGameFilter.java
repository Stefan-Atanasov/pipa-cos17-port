package com.oplus.vrr;

import android.util.Slog;

import com.android.server.LocalServices;
import com.android.server.display.color.DisplayTransformManager;

/**
 * pipa port (BUGS-TODO 22): the Game Assistant filters as a SurfaceFlinger colour matrix.
 *
 * OPPO devices apply Game Filter 2.0 and colour enhancement in the panel PQ block (SurfaceFlinger transaction 22031 ->
 * IDisplayPanelFeature feature 35 -> SDM PQ mode). pipa has no IDisplayPanelFeature HAL, so the original call does
 * nothing. OPlusSurfaceFlingerController.setGameFilter(int) also calls set() here: the filter becomes one level of the
 * DisplayTransformManager colour matrix, so it stacks with Night Light, grayscale and the other levels.
 *
 * Modes (from OplusGames): 0..99 = filter index (0 = off), 100..199 = colour enhancement index + 100 (100 = off).
 * Filter indices: my_product/etc/extension/sys_gamespace_function.json color_filter_2_0_filter_index. The matrices are
 * approximations of the OPPO 3D LUT presets.
 */
public final class PipaGameFilter {
    private static final String TAG = "PipaGameFilter";
    /** After LEVEL_COLOR_MATRIX_SATURATION (150), before GRAYSCALE (200) and INVERT (300). */
    private static final int LEVEL = 151;
    // linear-light luminance weights, as ColorDisplayService's saturation matrix
    private static final float LR = 0.231f, LG = 0.715f, LB = 0.054f;

    private static int sFilter, sEnhance;

    private PipaGameFilter() {}

    public static void set(int mode) {
        try {
            float[] m;
            synchronized (PipaGameFilter.class) {
                if (mode >= 100 && mode < 200) sEnhance = mode - 100;
                else if (mode >= 0 && mode < 100) sFilter = mode;
                else return;
                m = mul(filter(sFilter), saturation(sEnhance <= 0 ? 1f : 1f + 0.06f * Math.min(sEnhance, 5)));
            }
            DisplayTransformManager dtm = LocalServices.getService(DisplayTransformManager.class);
            if (dtm == null) return;
            dtm.setColorMatrix(LEVEL, isIdentity(m) ? null : m);
            Slog.i(TAG, "mode " + mode + ": filter " + sFilter + ", enhance " + sEnhance);
        } catch (Throwable t) {
            Slog.e(TAG, "mode " + mode, t);
        }
    }

    /** Column-major 4x4: out.r = m[0]*r + m[4]*g + m[8]*b + m[12]. */
    private static float[] rgb(float rr, float rg, float rb, float gr, float gg, float gb, float br, float bg, float bb,
                               float or, float og, float ob) {
        return new float[] {rr, gr, br, 0, rg, gg, bg, 0, rb, gb, bb, 0, or, og, ob, 1};
    }

    private static float[] identity() {
        return rgb(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0);
    }

    private static float[] saturation(float s) {
        float i = 1 - s;
        return rgb(LR * i + s, LG * i, LB * i,
                   LR * i, LG * i + s, LB * i,
                   LR * i, LG * i, LB * i + s, 0, 0, 0);
    }

    private static float[] gain(float r, float g, float b) {
        return rgb(r, 0, 0, 0, g, 0, 0, 0, b, 0, 0, 0);
    }

    /** Contrast around mid grey (c > 1 = more contrast). */
    private static float[] contrast(float c) {
        float o = 0.5f * (1 - c);
        return rgb(c, 0, 0, 0, c, 0, 0, 0, c, o, o, o);
    }

    private static float[] filter(int f) {
        switch (f) {
            case 1:  // dreamland_roaming: soft, a little pink and vivid
                return mul(gain(1.04f, 0.97f, 1.04f), mul(saturation(1.15f), contrast(0.94f)));
            case 2:  // fenghuo_huijuan: warm old scroll
                return mul(gain(1.06f, 0.98f, 0.82f), saturation(0.80f));
            case 3:  // tactical_enhancement: contrast and colour for spotting
                return mul(contrast(1.12f), saturation(1.30f));
            case 4:  // ultra_hd: crisp and vivid
                return mul(contrast(1.06f), saturation(1.20f));
            case 6:  // bright: lifts the shadows
                return rgb(0.92f, 0, 0, 0, 0.92f, 0, 0, 0, 0.92f, 0.08f, 0.08f, 0.08f);
            case 7:  // film: muted, warm, low contrast
                return mul(gain(1.04f, 1.0f, 0.92f), mul(saturation(0.75f), contrast(0.90f)));
            case 8: {  // night_vision_device: green monochrome
                float k = 1.15f;
                return rgb(0.25f * LR * k, 0.25f * LG * k, 0.25f * LB * k,
                           LR * k, LG * k, LB * k,
                           0.25f * LR * k, 0.25f * LG * k, 0.25f * LB * k, 0, 0.02f, 0);
            }
            case 9:  // fantasy_vision: cool violet, very vivid
                return mul(gain(1.0f, 0.94f, 1.10f), saturation(1.35f));
            default:
                return identity();
        }
    }

    /** a * b (column-major): applies b first, then a. */
    private static float[] mul(float[] a, float[] b) {
        float[] r = new float[16];
        for (int c = 0; c < 4; c++) {
            for (int row = 0; row < 4; row++) {
                float s = 0;
                for (int k = 0; k < 4; k++) s += a[k * 4 + row] * b[c * 4 + k];
                r[c * 4 + row] = s;
            }
        }
        return r;
    }

    private static boolean isIdentity(float[] m) {
        float[] i = identity();
        for (int k = 0; k < 16; k++) if (Math.abs(m[k] - i[k]) > 1e-4f) return false;
        return true;
    }
}
