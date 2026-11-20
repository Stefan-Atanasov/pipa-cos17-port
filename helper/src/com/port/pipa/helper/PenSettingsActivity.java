package com.port.pipa.helper;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * helper 2.5 (BUGS 153): settings and live test for the two Xiaomi Smart Pen buttons.
 *
 * Kernel walt-hi12 (pipa_pen_buttons.c) decides each press once. Pen near the screen: stylus buttons in the pen
 * events (apps decide: eraser, menu). Pen away (far_mode): 0 off, 1 page down/up (HyperOS), 2 stylus buttons,
 * 3 custom actions (short F21/F22, double F19/F20); a long press (F23/F24) runs an action in modes 1-3.
 * pen_keys.sh runs the actions. One global setting, "pipa_pen_buttons":
 *   "<far_mode> <long_ms> <front long> <back long> <front short> <back short> <front double> <back double>"
 * Actions: a name from ACTIONS, or app:<package>/<activity>. While this screen is open, "pipa_pen_test" = 1:
 * pen_keys.sh sends the presses here (broadcast PEN_ACTION) instead of running them.
 */
public final class PenSettingsActivity extends Activity {
    static final String KEY = "pipa_pen_buttons", TEST = "pipa_pen_test";
    static final String ACTION_PRESS = "com.port.pipa.helper.PEN_ACTION";
    static final String DEFAULT = "1 380 quicknote screenshot none none none none";
    static final String APP = "app";   // spinner entry "Open an app..."
    static final String[] ACTIONS = { "none", "screenshot", "quicknote", "quickpaint", "circle", "assistant",
            "playpause", "next", "previous", "volup", "voldown", "flashlight", "dnd", "rotate", "lock", "notifications", "quicksettings", "camera", "back", "home", "recents", APP };
    static final int[] LABELS = { R.string.pen_a_none, R.string.pen_a_screenshot, R.string.pen_a_quicknote,
            R.string.pen_a_quickpaint, R.string.pen_a_circle, R.string.pen_a_assistant, R.string.pen_a_playpause,
            R.string.pen_a_next, R.string.pen_a_previous, R.string.pen_a_volup, R.string.pen_a_voldown,
            R.string.pen_a_flashlight, R.string.pen_a_dnd, R.string.pen_a_rotate, R.string.pen_a_lock, R.string.pen_a_notifications, R.string.pen_a_quicksettings,
            R.string.pen_a_camera, R.string.pen_a_back, R.string.pen_a_home, R.string.pen_a_recents,
            R.string.pen_a_app };
    // slot order = setting order after long_ms
    private static final int F_LONG = 0, B_LONG = 1, F_SHORT = 2, B_SHORT = 3, F_DOUBLE = 4, B_DOUBLE = 5;
    private static final long NEAR_MS = 200;

    private int farMode = 1, longMs = 380;
    private final String[] slot = { "quicknote", "screenshot", "none", "none", "none", "none" };
    private final Spinner[] spin = new Spinner[6];
    private final View[] customRows = new View[4];
    private PenView pen;
    private TextView status, holdLabel;
    private RadioGroup farGroup;
    private SeekBar holdBar;
    private final Handler h = new Handler(Looper.getMainLooper());
    private long lastHover;
    private int heldButtons;
    private boolean loading;

    private final Runnable nearOff = () -> {
        if (System.currentTimeMillis() - lastHover >= NEAR_MS) pen.near(false);
    };

    private final BroadcastReceiver pressRx = new BroadcastReceiver() {
        @Override
        public void onReceive(Context c, Intent i) {
            int b = i.getIntExtra("button", -1);
            String kind = i.getStringExtra("kind");
            if ((b != 0 && b != 1) || kind == null) return;
            int s, k, what;
            switch (kind) {
                case "long": s = b == 0 ? F_LONG : B_LONG; k = PenView.LONG; what = R.string.pen_k_long; break;
                case "double": s = b == 0 ? F_DOUBLE : B_DOUBLE; k = PenView.DOUBLE; what = R.string.pen_k_double; break;
                default: s = b == 0 ? F_SHORT : B_SHORT; k = PenView.FAR; what = R.string.pen_k_short; break;
            }
            pen.flash(b, k);
            setStatus(getString(R.string.pen_st_action, buttonName(b), getString(what), label(slot[s])));
        }
    };

    private int px(float dp) { return (int) (dp * getResources().getDisplayMetrics().density + 0.5f); }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        Ui.transitions(this);
        parse(Settings.Global.getString(getContentResolver(), KEY));

        LinearLayout page = Ui.page(this, getString(R.string.pen_title), true);
        LinearLayout root = Ui.card(page);
        root.setPadding(px(20), px(8), px(20), px(20));

        pen = new PenView(this);
        root.addView(pen);
        status = text(getString(R.string.pen_st_hint), 14, false);
        status.setGravity(Gravity.CENTER_HORIZONTAL);
        status.setMinLines(2);
        root.addView(status);

        root.addView(header(R.string.pen_h_far));
        farGroup = new RadioGroup(this);
        int[] farLabels = { R.string.pen_far_off, R.string.pen_far_page, R.string.pen_far_stylus, R.string.pen_far_custom };
        for (int m = 0; m < farLabels.length; m++) {
            RadioButton rb = new RadioButton(this);
            rb.setId(View.generateViewId());
            rb.setTag(m);
            rb.setText(farLabels[m]);
            farGroup.addView(rb);
        }
        farGroup.setOnCheckedChangeListener((g, id) -> {
            View v = g.findViewById(id);
            if (v == null || loading) return;
            farMode = (Integer) v.getTag();
            updateEnabled();
            save();
        });
        root.addView(farGroup);
        root.addView(note(R.string.pen_far_note));

        root.addView(header(R.string.pen_h_actions));
        root.addView(sub(R.string.pen_btn_front_long));
        customRows[0] = row(root, R.string.pen_short, F_SHORT);
        customRows[1] = row(root, R.string.pen_double, F_DOUBLE);
        row(root, R.string.pen_long, F_LONG);
        root.addView(sub(R.string.pen_btn_back));
        customRows[2] = row(root, R.string.pen_short, B_SHORT);
        customRows[3] = row(root, R.string.pen_double, B_DOUBLE);
        row(root, R.string.pen_long, B_LONG);

        holdLabel = text("", 15, false);
        holdLabel.setPadding(0, px(16), 0, 0);
        root.addView(holdLabel);
        holdBar = new SeekBar(this);
        holdBar.setMax((800 - 250) / 10);
        holdBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean user) {
                longMs = 250 + p * 10;
                holdLabel.setText(getString(R.string.pen_hold, longMs));
            }
            @Override public void onStartTrackingTouch(SeekBar s) { }
            @Override public void onStopTrackingTouch(SeekBar s) { save(); }
        });
        root.addView(holdBar);

        root.addView(header(R.string.pen_h_near));
        root.addView(note(R.string.pen_near_note));

        Button reset = new Button(this);
        reset.setText(R.string.pen_reset);
        reset.setOnClickListener(v -> {
            parse(DEFAULT);
            save();
            refresh();
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = px(16);
        root.addView(reset, lp);

        refresh();
        Ui.enter(page);
    }

    /** one "<label>  [spinner]" row; returns the row */
    private View row(LinearLayout parent, int labelRes, int s) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setGravity(Gravity.CENTER_VERTICAL);
        TextView t = text(getString(labelRes), 15, false);
        r.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        Spinner sp = new Spinner(this);
        spin[s] = sp;
        sp.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
                if (loading) return;
                String a = (String) ((ActionAdapter) sp.getAdapter()).value(pos);
                if (APP.equals(a)) { pickApp(s); return; }
                if (!a.equals(slot[s])) { slot[s] = a; save(); }
            }
            @Override public void onNothingSelected(AdapterView<?> p) { }
        });
        r.addView(sp, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.4f));
        parent.addView(r);
        return r;
    }

    /** spinner items: the fixed actions, plus the chosen app (if any) */
    private final class ActionAdapter extends ArrayAdapter<String> {
        private final List<String> values = new ArrayList<>();
        ActionAdapter(String cur) {
            super(PenSettingsActivity.this, android.R.layout.simple_spinner_item);
            setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
            if (cur.startsWith("app:")) { values.add(cur); add(label(cur)); }
            for (int i = 0; i < ACTIONS.length; i++) { values.add(ACTIONS[i]); add(getString(LABELS[i])); }
        }
        String value(int pos) { return values.get(pos); }
        int indexOf(String v) { int i = values.indexOf(v); return i < 0 ? values.indexOf("none") : i; }
    }

    private void bindSpinner(int s) {
        ActionAdapter ad = new ActionAdapter(slot[s]);
        spin[s].setAdapter(ad);
        spin[s].setSelection(ad.indexOf(slot[s]), false);
    }

    private void pickApp(int s) {
        PackageManager pm = getPackageManager();
        Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> list = pm.queryIntentActivities(main, 0);
        List<String[]> apps = new ArrayList<>();   // label, component
        List<Drawable> icons = new ArrayList<>();
        Collections.sort(list, (x, y) -> x.loadLabel(pm).toString().compareToIgnoreCase(y.loadLabel(pm).toString()));
        for (ResolveInfo ri : list) {
            apps.add(new String[] { ri.loadLabel(pm).toString(),
                    ri.activityInfo.packageName + "/" + ri.activityInfo.name });
            icons.add(ri.loadIcon(pm));
        }
        ArrayAdapter<String[]> ad = new ArrayAdapter<String[]>(this, android.R.layout.simple_list_item_1, apps) {
            @Override public View getView(int pos, View v, ViewGroup parent) {
                TextView t = (TextView) super.getView(pos, v, parent);
                t.setText(apps.get(pos)[0]);
                Drawable d = icons.get(pos);
                d.setBounds(0, 0, px(32), px(32));
                t.setCompoundDrawablesRelative(d, null, null, null);
                t.setCompoundDrawablePadding(px(16));
                return t;
            }
        };
        new AlertDialog.Builder(this)
                .setTitle(R.string.pen_pick_app)
                .setAdapter(ad, (d, which) -> {
                    slot[s] = "app:" + apps.get(which)[1];
                    save();
                    loading = true;
                    bindSpinner(s);
                    loading = false;
                })
                .setOnCancelListener(d -> { loading = true; bindSpinner(s); loading = false; })
                .show();
    }

    private String label(String a) {
        if (a.startsWith("app:")) {
            ComponentName cn = ComponentName.unflattenFromString(a.substring(4));
            if (cn != null) {
                try {
                    return getString(R.string.pen_a_open,
                            getPackageManager().getActivityInfo(cn, 0).loadLabel(getPackageManager()));
                } catch (PackageManager.NameNotFoundException ignored) { }
            }
            return a.substring(4);
        }
        for (int i = 0; i < ACTIONS.length; i++) if (ACTIONS[i].equals(a)) return getString(LABELS[i]);
        return a;
    }

    private String buttonName(int b) { return getString(b == 0 ? R.string.pen_btn_front : R.string.pen_btn_back); }

    private TextView text(String s, int sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, px(6), 0, px(2));
        return t;
    }

    private TextView header(int res) {
        TextView t = text(getString(res), 13, true);
        t.setTextColor(Ui.accent(this));
        t.setPadding(0, px(24), 0, px(4));
        return t;
    }

    private TextView sub(int res) {
        TextView t = text(getString(res), 15, true);
        t.setPadding(0, px(12), 0, 0);
        return t;
    }

    private TextView note(int res) {
        TextView t = text(getString(res), 13, false);
        t.setAlpha(0.7f);
        return t;
    }

    private void parse(String v) {
        String[] d = DEFAULT.split(" ");
        String[] p = v == null ? d : v.trim().split("\\s+");
        farMode = 1; longMs = 380;
        try {
            farMode = Math.max(0, Math.min(3, Integer.parseInt(p[0])));
            if (p.length > 1) longMs = Math.max(250, Math.min(800, Integer.parseInt(p[1])));
        } catch (NumberFormatException ignored) { }
        for (int i = 0; i < 6; i++) slot[i] = p.length > i + 2 ? p[i + 2] : d[i + 2];
    }

    private void refresh() {
        loading = true;
        for (int i = 0; i < farGroup.getChildCount(); i++) {
            RadioButton rb = (RadioButton) farGroup.getChildAt(i);
            rb.setChecked((Integer) rb.getTag() == farMode);
        }
        for (int s = 0; s < 6; s++) bindSpinner(s);
        holdBar.setProgress((longMs - 250) / 10);
        holdLabel.setText(getString(R.string.pen_hold, longMs));
        updateEnabled();
        loading = false;
    }

    /** short and double press need "custom actions"; nothing works away from the screen in mode 0 */
    private void updateEnabled() {
        for (View r : customRows) setEnabled(r, farMode == 3);
        for (int s : new int[] { F_LONG, B_LONG }) setEnabled((View) spin[s].getParent(), farMode != 0);
        holdBar.setEnabled(farMode != 0);
        holdLabel.setAlpha(farMode != 0 ? 1f : 0.4f);
    }

    private static void setEnabled(View v, boolean on) {
        v.setAlpha(on ? 1f : 0.4f);
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) g.getChildAt(i).setEnabled(on);
        }
    }

    private void save() {
        StringBuilder sb = new StringBuilder().append(farMode).append(' ').append(longMs);
        for (String a : slot) sb.append(' ').append(a);
        put(KEY, sb.toString());
    }

    private void put(String k, String v) {
        try {
            Settings.Global.putString(getContentResolver(), k, v);
        } catch (SecurityException e) {
            Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
        }
    }

    private void setStatus(String s) {
        status.setText(s);
        status.setAlpha(0.4f);
        status.animate().alpha(1f).setDuration(200).start();
    }

    @Override
    protected void onResume() {
        super.onResume();
        put(TEST, "1");
        registerReceiver(pressRx, new IntentFilter(ACTION_PRESS), Context.RECEIVER_EXPORTED);
    }

    @Override
    protected void onPause() {
        put(TEST, "0");
        try { unregisterReceiver(pressRx); } catch (IllegalArgumentException ignored) { }
        super.onPause();
    }

    // ---- live test: near = stylus buttons in the pen events; away = keys from the kernel's pipa_pen_buttons

    private void penEvent(MotionEvent e) {
        int tool = e.getToolType(0);
        if (tool != MotionEvent.TOOL_TYPE_STYLUS && tool != MotionEvent.TOOL_TYPE_ERASER) return;
        lastHover = System.currentTimeMillis();
        pen.near(true);
        h.removeCallbacks(nearOff);
        h.postDelayed(nearOff, NEAR_MS);
        int bs = e.getButtonState(), held = 0;
        if ((bs & MotionEvent.BUTTON_STYLUS_PRIMARY) != 0) held |= 1;
        if ((bs & MotionEvent.BUTTON_STYLUS_SECONDARY) != 0) held |= 2;
        for (int b = 0; b < 2; b++) {
            boolean now = (held & (1 << b)) != 0, was = (heldButtons & (1 << b)) != 0;
            if (now != was) {
                pen.press(b, PenView.NEAR, now);
                if (now) setStatus(getString(R.string.pen_st_near, buttonName(b)));
            }
        }
        heldButtons = held;
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent e) {
        penEvent(e);
        return super.dispatchGenericMotionEvent(e);
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent e) {
        penEvent(e);
        return super.dispatchTouchEvent(e);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        int b = -1;
        boolean page = false;
        switch (e.getKeyCode()) {
            case KeyEvent.KEYCODE_PAGE_DOWN: b = 0; page = true; break;
            case KeyEvent.KEYCODE_PAGE_UP: b = 1; page = true; break;
            case KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY: b = 0; break;
            case KeyEvent.KEYCODE_STYLUS_BUTTON_SECONDARY: b = 1; break;
            default: break;
        }
        if (b < 0) return super.dispatchKeyEvent(e);
        if (e.getAction() == KeyEvent.ACTION_DOWN && e.getRepeatCount() == 0) {
            pen.flash(b, PenView.FAR);
            setStatus(getString(page ? R.string.pen_st_far_page : R.string.pen_st_far_stylus, buttonName(b)));
        }
        return true;   // the test does not scroll the page
    }
}
