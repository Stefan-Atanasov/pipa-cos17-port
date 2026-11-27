package com.port.pipa.helper;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.animation.DecelerateInterpolator;
import android.widget.CompoundButton;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

/**
 * helper 2.5: the look of the Pipa Helper app, plain Views (no AndroidX): ColorOS-like large title, rounded cards,
 * rows with icon, title, summary and a switch or a chevron; pages slide in, cards fade up one after the other.
 * Colours come from the wallpaper palette (system_accent1 / system_neutral1), light and dark.
 */
final class Ui {
    private Ui() { }

    static int px(Context c, float dp) { return (int) (dp * c.getResources().getDisplayMetrics().density + 0.5f); }

    static boolean night(Context c) {
        return (c.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
    }

    static int bg(Context c) {
        return c.getColor(night(c) ? android.R.color.system_neutral1_900 : android.R.color.system_neutral1_50);
    }

    static int card(Context c) {
        return night(c) ? c.getColor(android.R.color.system_neutral1_800) : 0xFFFFFFFF;
    }

    static int accent(Context c) {
        return c.getColor(night(c) ? android.R.color.system_accent1_200 : android.R.color.system_accent1_600);
    }

    static int accentSoft(Context c) {
        return c.getColor(night(c) ? android.R.color.system_accent1_800 : android.R.color.system_accent1_100);
    }

    static int text(Context c) {
        return c.getColor(night(c) ? android.R.color.system_neutral1_50 : android.R.color.system_neutral1_900);
    }

    static int sub(Context c) {
        return c.getColor(night(c) ? android.R.color.system_neutral2_300 : android.R.color.system_neutral2_600);
    }

    /** the page frame: large title (and a back arrow), scrolling content; returns the content column */
    static LinearLayout page(Activity a, CharSequence title, boolean back) {
        a.getWindow().getDecorView().setBackgroundColor(bg(a));
        ScrollView sv = new ScrollView(a);
        sv.setClipToPadding(false);
        sv.setFillViewport(true);
        LinearLayout col = new LinearLayout(a);
        col.setOrientation(LinearLayout.VERTICAL);
        int side = px(a, 20);
        col.setPadding(side, 0, side, px(a, 24));
        FrameLayout frame = new Narrow(a);        // the column keeps a readable width in landscape
        frame.addView(col, narrow(a));
        sv.addView(frame, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        // edge-to-edge (target 37): keep the content clear of the status and navigation bars
        sv.setOnApplyWindowInsetsListener((v, in) -> {
            android.graphics.Insets s = in.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(s.left, s.top, s.right, s.bottom);
            return WindowInsets.CONSUMED;
        });

        LinearLayout head = new LinearLayout(a);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.setPadding(0, px(a, back ? 8 : 28), 0, px(a, 12));
        if (back) {
            ImageView b = new ImageView(a);
            b.setImageResource(R.drawable.ic_back);
            b.setImageTintList(ColorStateList.valueOf(text(a)));
            b.setPadding(px(a, 10), px(a, 10), px(a, 10), px(a, 10));
            b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22808080), null, oval()));
            b.setContentDescription(a.getString(R.string.ui_back));
            b.setOnClickListener(v -> a.finish());
            head.addView(b, new LinearLayout.LayoutParams(px(a, 44), px(a, 44)));
        }
        TextView t = new TextView(a);
        t.setText(title);
        t.setTextColor(text(a));
        t.setTextSize(back ? 24 : 32);
        t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        t.setPadding(back ? px(a, 6) : px(a, 4), 0, 0, 0);
        head.addView(t);
        col.addView(head);
        a.setContentView(sv);
        return col;
    }

    private static GradientDrawable oval() {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.OVAL);
        d.setColor(0xFFFFFFFF);
        return d;
    }

    private static GradientDrawable rounded(int color, float r) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(r);
        return d;
    }

    /** a rounded card for rows; add it to the page with addCard */
    static LinearLayout card(LinearLayout parent) {
        Context c = parent.getContext();
        LinearLayout k = new LinearLayout(c);
        k.setOrientation(LinearLayout.VERTICAL);
        k.setBackground(rounded(card(c), px(c, 20)));
        k.setClipToOutline(true);
        k.setPadding(0, px(c, 4), 0, px(c, 4));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = px(c, 12);
        parent.addView(k, lp);
        return k;
    }

    /** small grey heading above a card */
    static void header(LinearLayout parent, CharSequence s) {
        Context c = parent.getContext();
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(13);
        t.setTextColor(sub(c));
        t.setPadding(px(c, 16), px(c, 18), px(c, 16), 0);
        parent.addView(t);
    }

    /** grey note text (inside a card or on the page) */
    static TextView note(LinearLayout parent, CharSequence s) {
        Context c = parent.getContext();
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(13);
        t.setTextColor(sub(c));
        t.setLineSpacing(0, 1.15f);
        t.setPadding(px(c, 16), px(c, 10), px(c, 16), px(c, 12));
        parent.addView(t);
        return t;
    }

    /** round tinted badge with a symbol (menu icons) */
    static TextView badge(Context c, String symbol) {
        TextView b = new TextView(c);
        b.setText(symbol);
        b.setTextSize(18);
        b.setGravity(Gravity.CENTER);
        b.setTextColor(accent(c));
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.OVAL);
        d.setColor(accentSoft(c));
        b.setBackground(d);
        return b;
    }

    /** one row: [badge] title / summary [end]; returns the row; the summary view is tagged "summary" */
    static LinearLayout row(LinearLayout card, String symbol, CharSequence title, CharSequence summary, View end,
            View.OnClickListener click) {
        Context c = card.getContext();
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setMinimumHeight(px(c, 64));
        r.setPadding(px(c, 16), px(c, 10), px(c, 16), px(c, 10));
        if (symbol != null) {
            LinearLayout.LayoutParams bl = new LinearLayout.LayoutParams(px(c, 38), px(c, 38));
            bl.rightMargin = px(c, 14);
            r.addView(badge(c, symbol), bl);
        }
        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(LinearLayout.VERTICAL);
        TextView t = new TextView(c);
        t.setText(title);
        t.setTextSize(16);
        t.setTextColor(text(c));
        texts.addView(t);
        TextView s = new TextView(c);
        s.setTag("summary");
        s.setTextSize(13);
        s.setTextColor(sub(c));
        s.setPadding(0, px(c, 2), 0, 0);
        s.setMaxLines(4);
        s.setEllipsize(TextUtils.TruncateAt.END);
        if (summary == null || summary.length() == 0) s.setVisibility(View.GONE);
        else s.setText(summary);
        texts.addView(s);
        r.addView(texts, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        if (end != null) {
            LinearLayout.LayoutParams el = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT);
            el.leftMargin = px(c, 12);
            r.addView(end, el);
        }
        if (click != null) {
            r.setBackground(new RippleDrawable(ColorStateList.valueOf(0x1F808080), null,
                    rounded(0xFFFFFFFF, 0)));
            r.setOnClickListener(click);
        }
        card.addView(r);
        return r;
    }

    static void setSummary(View row, CharSequence s) {
        TextView t = row.findViewWithTag("summary");
        if (t == null) return;
        t.setText(s);
        t.setVisibility(s == null || s.length() == 0 ? View.GONE : View.VISIBLE);
    }

    static TextView chevron(Context c) {
        TextView v = new TextView(c);
        v.setText("›");
        v.setTextSize(22);
        v.setTextColor(sub(c));
        return v;
    }

    /** a row that opens something */
    static LinearLayout link(LinearLayout card, String symbol, CharSequence title, CharSequence summary,
            View.OnClickListener click) {
        return row(card, symbol, title, summary, chevron(card.getContext()), click);
    }

    /** a row with a switch; the whole row toggles it */
    static Switch toggle(LinearLayout card, String symbol, CharSequence title, CharSequence summary, boolean on,
            CompoundButton.OnCheckedChangeListener l) {
        Context c = card.getContext();
        Switch sw = new Switch(c);
        sw.setChecked(on);
        sw.setThumbTintList(null);
        sw.setTrackTintList(new ColorStateList(new int[][] { { android.R.attr.state_checked }, { } },
                new int[] { accent(c), c.getColor(night(c) ? android.R.color.system_neutral1_600
                        : android.R.color.system_neutral1_200) }));
        sw.setOnCheckedChangeListener(l);
        row(card, symbol, title, summary, sw, v -> sw.toggle());
        return sw;
    }

    /** thin line between rows */
    static void divider(LinearLayout card) {
        Context c = card.getContext();
        View d = new View(c);
        d.setBackgroundColor(night(c) ? 0x22FFFFFF : 0x14000000);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1);
        lp.leftMargin = px(c, 68);
        lp.rightMargin = px(c, 16);
        card.addView(d, lp);
    }

    /** cards fade up one after the other when a page opens */
    static void enter(LinearLayout col) {
        DecelerateInterpolator di = new DecelerateInterpolator(2f);
        for (int i = 0; i < col.getChildCount(); i++) {
            View v = col.getChildAt(i);
            v.setAlpha(0f);
            v.setTranslationY(px(col.getContext(), 18));
            v.animate().alpha(1f).translationY(0).setStartDelay(30L * i).setDuration(320).setInterpolator(di).start();
        }
    }

    /** open a page of this app with the slide animation */
    static void open(Activity a, Intent i) {
        a.startActivity(i);
        if (Build.VERSION.SDK_INT < 34) a.overridePendingTransition(R.anim.page_in, R.anim.page_hold);
    }

    /** call in onCreate of each page: slide in on open, slide out on back */
    static void transitions(Activity a) {
        if (Build.VERSION.SDK_INT >= 34) {
            a.overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, R.anim.page_in, R.anim.page_hold);
            a.overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, R.anim.page_hold, R.anim.page_out);
        }
    }

    /** the column inside a {@link Narrow} frame: full frame width, centred */
    static FrameLayout.LayoutParams narrow(Context c) {
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.gravity = Gravity.CENTER_HORIZONTAL;
        return lp;
    }

    /**
     * 3.8 (BUGS 218): centres its column at up to 760 dp, never wider than the frame itself. Before, the column took
     * min(760 dp, display width): in a floating window (or split view) the window is narrower than the display, so the
     * column overflowed and its sides were cut off. Measuring against the frame's own width follows every resize.
     */
    static final class Narrow extends FrameLayout {
        private final int max;
        Narrow(Context c) { super(c); max = px(c, 760); }
        @Override protected void onMeasure(int wSpec, int hSpec) {
            int w = MeasureSpec.getSize(wSpec);
            super.onMeasure(MeasureSpec.makeMeasureSpec(Math.min(w, max), MeasureSpec.EXACTLY), hSpec);
            setMeasuredDimension(w, getMeasuredHeight());   // full width; onLayout centres the column
        }
    }
}
