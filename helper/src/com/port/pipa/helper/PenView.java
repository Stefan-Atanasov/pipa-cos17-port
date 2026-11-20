package com.port.pipa.helper;

import android.animation.ValueAnimator;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.View;
import android.view.animation.DecelerateInterpolator;

/**
 * helper 2.5 (BUGS 153): the Xiaomi Smart Pen as a picture for the pen settings. The tip points left; the front
 * button is next to the tip, the back button behind it. press() lights a button while it is held, flash() lights it
 * once (a press with the pen away). The colour tells the path: near the screen (accent), away short (green),
 * away double (purple), away long (orange). The "near" glow around the tip shows that the screen sees the pen.
 */
public final class PenView extends View {
    static final int NEAR = 1, FAR = 2, LONG = 3, DOUBLE = 4;

    private final Paint body = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint edge = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint btn = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint glowP = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint lit = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();
    private final RectF r = new RectF();
    private final float[] glow = new float[2];
    private final int[] kind = new int[2];
    private final ValueAnimator[] anim = new ValueAnimator[2];
    private float tipGlow, tipTarget;
    private ValueAnimator tipAnim;
    private final float dp;

    public PenView(Context c) {
        super(c);
        dp = c.getResources().getDisplayMetrics().density;
        boolean night = (c.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        body.setColor(c.getColor(night ? android.R.color.system_neutral1_700 : android.R.color.system_neutral1_100));
        edge.setStyle(Paint.Style.STROKE);
        edge.setStrokeWidth(1.5f * dp);
        edge.setColor(c.getColor(night ? android.R.color.system_neutral1_400 : android.R.color.system_neutral1_400));
        btn.setColor(c.getColor(night ? android.R.color.system_neutral1_500 : android.R.color.system_neutral1_300));
    }

    private int color(int k) {
        switch (k) {
            case FAR: return 0xFF34A853;
            case LONG: return 0xFFF29900;
            case DOUBLE: return 0xFFA142F4;
            default: return getContext().getColor(android.R.color.system_accent1_500);
        }
    }

    private void animateTo(int b, float to, long ms) {
        if (anim[b] != null) anim[b].cancel();
        ValueAnimator a = ValueAnimator.ofFloat(glow[b], to);
        a.setDuration(ms);
        a.setInterpolator(new DecelerateInterpolator());
        a.addUpdateListener(v -> { glow[b] = (float) v.getAnimatedValue(); invalidate(); });
        anim[b] = a;
        a.start();
    }

    /** button b (0 front, 1 back) held (down) or released, path k */
    void press(int b, int k, boolean down) {
        kind[b] = k;
        animateTo(b, down ? 1f : 0f, down ? 120 : 420);
    }

    /** one short or long press with the pen away */
    void flash(int b, int k) {
        kind[b] = k;
        if (anim[b] != null) anim[b].cancel();
        ValueAnimator a = ValueAnimator.ofFloat(1f, 0f);
        a.setDuration(k == LONG ? 900 : 600);
        a.setInterpolator(new DecelerateInterpolator(1.5f));
        a.addUpdateListener(v -> { glow[b] = (float) v.getAnimatedValue(); invalidate(); });
        anim[b] = a;
        a.start();
    }

    /** the screen sees the pen (hover or touch) */
    void near(boolean on) {
        float to = on ? 1f : 0f;
        if (to == tipTarget) return;
        tipTarget = to;
        if (tipAnim != null) tipAnim.cancel();
        tipAnim = ValueAnimator.ofFloat(tipGlow, to);
        tipAnim.setDuration(on ? 150 : 500);
        tipAnim.addUpdateListener(v -> { tipGlow = (float) v.getAnimatedValue(); invalidate(); });
        tipAnim.start();
    }

    @Override
    protected void onMeasure(int w, int h) {
        setMeasuredDimension(getDefaultSize(getSuggestedMinimumWidth(), w), (int) (96 * dp));
    }

    @Override
    protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight();
        float len = Math.min(w - 32 * dp, 560 * dp), x0 = (w - len) / 2, cy = h / 2, rad = 9 * dp;
        float tipLen = len * 0.09f, bx0 = x0 + tipLen;
        // tip glow (pen near the screen)
        if (tipGlow > 0.01f) {
            glowP.setColor(color(NEAR));
            glowP.setAlpha((int) (90 * tipGlow));
            c.drawCircle(x0, cy, 18 * dp * (0.6f + 0.4f * tipGlow), glowP);
        }
        // tip cone
        path.reset();
        path.moveTo(x0, cy);
        path.lineTo(bx0, cy - rad);
        path.lineTo(bx0, cy + rad);
        path.close();
        c.drawPath(path, body);
        c.drawPath(path, edge);
        // body
        r.set(bx0, cy - rad, x0 + len, cy + rad);
        c.drawRoundRect(r, rad, rad, body);
        c.drawRoundRect(r, rad, rad, edge);
        // buttons: front next to the tip, back behind it (on the top edge)
        float[] bxs = { bx0 + len * 0.10f, bx0 + len * 0.22f };
        for (int b = 0; b < 2; b++) {
            float bw = len * 0.075f, bh = 4 * dp, bx = bxs[b];
            if (glow[b] > 0.01f) {
                glowP.setColor(color(kind[b]));
                glowP.setAlpha((int) (110 * glow[b]));
                r.set(bx - 6 * dp, cy - rad - bh - 7 * dp, bx + bw + 6 * dp, cy - rad + 5 * dp);
                c.drawRoundRect(r, 10 * dp, 10 * dp, glowP);
            }
            r.set(bx, cy - rad - bh, bx + bw, cy - rad + 1 * dp);
            c.drawRoundRect(r, 2 * dp, 2 * dp, btn);
            if (glow[b] > 0.01f) {
                lit.setColor(color(kind[b]));
                lit.setAlpha((int) (255 * glow[b]));
                c.drawRoundRect(r, 2 * dp, 2 * dp, lit);
            }
        }
    }
}
