package com.port.pipa.helper;

import android.content.Context;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * A small dark pill at the top centre ("dynamic island" style) that fades in, stays a few seconds
 * and fades out. Drawn as an application overlay, so it needs the "display over other apps"
 * permission (appop SYSTEM_ALERT_WINDOW; pre-granted in the ROM build).
 */
final class PenPill {
    private static final String TAG = "PipaHelper.Pill";
    private static final long SHOW_MS = 3000;
    private static final long FADE_MS = 200;

    private final Context ctx;
    private final WindowManager wm;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private LinearLayout view;
    private ImageView icon;
    private TextView label;
    private boolean attached;
    private final Runnable hide = this::hideNow;

    PenPill(Context ctx) {
        this.ctx = ctx;
        wm = ctx.getSystemService(WindowManager.class);
    }

    boolean isShowing() {
        return attached;
    }

    /** Thread-safe; the window work runs on the main thread. */
    void show(String text, boolean charging) {
        ui.post(() -> showNow(text, charging));
    }

    private void showNow(String text, boolean charging) {
        if (!Settings.canDrawOverlays(ctx)) {
            Log.w(TAG, "no overlay permission, pill skipped: " + text);
            return;
        }
        if (view == null) build();
        label.setText(text);
        icon.setColorFilter(charging ? 0xFF4CD964 : Color.WHITE);
        if (!attached) {
            view.setAlpha(0f);
            wm.addView(view, params());
            attached = true;
            view.animate().alpha(1f).setDuration(FADE_MS).start();
        }
        ui.removeCallbacks(hide);
        ui.postDelayed(hide, SHOW_MS);
    }

    private void hideNow() {
        if (!attached) return;
        view.animate().alpha(0f).setDuration(FADE_MS).withEndAction(() -> {
            if (attached) {
                wm.removeView(view);
                attached = false;
            }
        }).start();
    }

    private void build() {
        int pad = dp(14);
        view = new LinearLayout(ctx);
        view.setOrientation(LinearLayout.HORIZONTAL);
        view.setGravity(Gravity.CENTER_VERTICAL);
        view.setPadding(pad, dp(8), pad + dp(4), dp(8));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xF0000000);
        bg.setCornerRadius(dp(24));
        view.setBackground(bg);

        icon = new ImageView(ctx);
        icon.setImageResource(R.drawable.ic_pen);
        view.addView(icon, new LinearLayout.LayoutParams(dp(20), dp(20)));

        label = new TextView(ctx);
        label.setTextColor(Color.WHITE);
        label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.setMarginStart(dp(8));
        view.addView(label, lp);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
    }

    private WindowManager.LayoutParams params() {
        WindowManager.LayoutParams p = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        p.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        p.y = dp(10);
        p.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
        p.setTitle("PipaPenPill");
        return p;
    }

    private int dp(int v) {
        return Math.round(v * ctx.getResources().getDisplayMetrics().density);
    }
}
