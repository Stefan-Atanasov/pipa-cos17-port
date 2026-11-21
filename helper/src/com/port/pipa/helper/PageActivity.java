package com.port.pipa.helper;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.database.ContentObserver;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.Toast;

/**
 * helper 2.5: one menu page of the Pipa Helper app (EXTRA_PAGE). Switches write the settings that the ROM reads
 * (pipa_port service.sh, the helper keepers); a ColorOS setting gets a link to its ColorOS page, not a copy.
 */
public final class PageActivity extends Activity {
    static final String EXTRA_PAGE = "page";
    static final String REPO_ISSUES = "https://github.com/Stefan-Atanasov/pipa-cos17-port/issues";

    private final Handler h = new Handler(Looper.getMainLooper());
    private Runnable onChange;
    private final ContentObserver obs = new ContentObserver(h) {
        @Override public void onChange(boolean self) { if (onChange != null) onChange.run(); }
    };
    private String[] watched = new String[0];

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        Ui.transitions(this);
        String page = String.valueOf(getIntent().getStringExtra(EXTRA_PAGE));
        switch (page) {
            case "pen": pen(); break;
            case "keyboard": keyboard(); break;
            case "effects": effects(); break;
            case "games": games(); break;
            default: system(); break;
        }
    }

    private LinearLayout start(int title) {
        return Ui.page(this, getString(title), true);
    }

    private void watch(Runnable r, String... keys) {
        onChange = r;
        watched = keys;
        r.run();
    }

    @Override
    protected void onResume() {
        super.onResume();
        for (String k : watched) {
            getContentResolver().registerContentObserver(Settings.Global.getUriFor(k), false, obs);
        }
        if (onChange != null) onChange.run();
    }

    @Override
    protected void onPause() {
        getContentResolver().unregisterContentObserver(obs);
        super.onPause();
    }

    private void go(Intent i) {
        try {
            startActivity(i);
        } catch (ActivityNotFoundException e) {
            Toast.makeText(this, R.string.ui_no_page, Toast.LENGTH_SHORT).show();
        }
    }

    private Switch globalToggle(LinearLayout k, String sym, int title, int sum, String key, int def) {
        Switch[] ref = new Switch[1];
        ref[0] = Ui.toggle(k, sym, getString(title), getString(sum), Status.global(this, key, def), (sw, on) -> {
            if (!Status.putGlobal(this, key, on ? 1 : 0)) {
                Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
                sw.setChecked(!on);
            }
        });
        return ref[0];
    }

    // ------------------------------------------------------------------ Pen

    private static final int[] DBL_MODES = { 1, 2, 3, 0 };
    private static final int[] DBL_LABELS = { R.string.ipe_eraser, R.string.ipe_last_pen, R.string.ipe_pick_color,
            R.string.ipe_off };
    private static final int[] SGL_MODES = { 4, 1, 2, 3, 0 };
    private static final int[] SGL_LABELS = { R.string.ipe_wheel, R.string.ipe_eraser, R.string.ipe_last_pen,
            R.string.ipe_pick_color, R.string.ipe_off };

    private void pen() {
        LinearLayout col = start(R.string.m_pen);
        LinearLayout k = Ui.card(col);
        View state = Ui.link(k, "✎", getString(R.string.pen_name), "", v -> go(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS)));
        Ui.divider(k);
        View buttons = Ui.link(k, "◉", getString(R.string.pen_title), "",
                v -> Ui.open(this, new Intent(this, PenSettingsActivity.class)));

        k = Ui.card(col);
        globalToggle(k, "◎", R.string.pen_always, R.string.pen_always_sum, "pipa_pen_always", 0);

        Ui.header(col, getString(R.string.pen_h_oppo));
        k = Ui.card(col);
        View dbl = Ui.link(k, "✐", getString(R.string.ipe_front), "",
                v -> choose(R.string.ipe_front, "ipe_pencil_double_click", 1, DBL_MODES, DBL_LABELS));
        Ui.divider(k);
        View sgl = Ui.link(k, "◌", getString(R.string.ipe_back), "",
                v -> choose(R.string.ipe_back, "ipe_pencil_single_click", 4, SGL_MODES, SGL_LABELS));
        Ui.note(k, getString(R.string.ipe_note));
        Ui.enter(col);

        watch(() -> {
            boolean on = Status.penConnected(this);
            int bat = Status.penBattery(this);
            Ui.setSummary(state, on ? (bat >= 0 ? getString(R.string.hero_pen_bat, bat) : getString(R.string.hero_pen_on))
                    : getString(R.string.pen_not_connected));
            Ui.setSummary(buttons, buttonsSummary());
            Ui.setSummary(dbl, modeLabel(Settings.Global.getInt(getContentResolver(), "ipe_pencil_double_click", 1),
                    DBL_MODES, DBL_LABELS));
            Ui.setSummary(sgl, modeLabel(Settings.Global.getInt(getContentResolver(), "ipe_pencil_single_click", 4),
                    SGL_MODES, SGL_LABELS));
        }, "ipe_pencil_connect_state", "ipe_pencil_battery_level", "ipe_pencil_double_click",
                "ipe_pencil_single_click", PenSettingsActivity.KEY);
    }

    private String buttonsSummary() {
        String v = Settings.Global.getString(getContentResolver(), PenSettingsActivity.KEY);
        String[] p = (v == null ? PenSettingsActivity.DEFAULT : v).trim().split("\\s+");
        int[] far = { R.string.pen_far_off, R.string.pen_far_page, R.string.pen_far_stylus, R.string.pen_far_custom };
        int m = 1;
        try { m = Math.max(0, Math.min(3, Integer.parseInt(p[0]))); } catch (NumberFormatException ignored) { }
        return getString(R.string.pen_buttons_sum, getString(far[m]));
    }

    private String modeLabel(int mode, int[] modes, int[] labels) {
        for (int i = 0; i < modes.length; i++) if (modes[i] == mode) return getString(labels[i]);
        return String.valueOf(mode);
    }

    private void choose(int title, String key, int def, int[] modes, int[] labels) {
        int cur = Settings.Global.getInt(getContentResolver(), key, def), sel = 0;
        String[] items = new String[modes.length];
        for (int i = 0; i < modes.length; i++) {
            items[i] = getString(labels[i]);
            if (modes[i] == cur) sel = i;
        }
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setSingleChoiceItems(items, sel, (d, which) -> {
                    if (!Status.putGlobal(this, key, modes[which])) {
                        Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
                    }
                    d.dismiss();
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    // ------------------------------------------------------------------ Keyboard case

    private void keyboard() {
        LinearLayout col = start(R.string.m_keyboard);
        LinearLayout k = Ui.card(col);
        View state = Ui.row(k, "⌨", getString(R.string.kb_name), "", null, null);

        Ui.header(col, getString(R.string.kb_h_keys));
        k = Ui.card(col);
        View sup = Ui.link(k, "⌘", getString(R.string.kb_super), "", v -> chooseSuper());
        Ui.note(k, getString(R.string.kb_super_note));
        Ui.enter(col);
        watch(() -> {
            Ui.setSummary(state, getString(Status.keyboard(this) ? R.string.hero_kb_on : R.string.hero_kb_off));
            Ui.setSummary(sup, superLabel(Settings.Global.getString(getContentResolver(), "pipa_kb_super")));
        }, "pipa_kb_super");
    }

    private String superLabel(String a) {
        if (a == null || a.equals("default")) return getString(R.string.kb_super_default);
        if (a.startsWith("app:")) {
            android.content.ComponentName cn = android.content.ComponentName.unflattenFromString(a.substring(4));
            try {
                return getString(R.string.pen_a_open, getPackageManager().getActivityInfo(cn, 0).loadLabel(getPackageManager()));
            } catch (Exception e) {
                return a.substring(4);
            }
        }
        for (int i = 0; i < PenSettingsActivity.ACTIONS.length; i++) {
            if (PenSettingsActivity.ACTIONS[i].equals(a)) return getString(PenSettingsActivity.LABELS[i]);
        }
        return a;
    }

    private void chooseSuper() {
        java.util.List<String> keys = new java.util.ArrayList<>();
        java.util.List<String> labels = new java.util.ArrayList<>();
        keys.add("default");
        labels.add(getString(R.string.kb_super_default));
        for (int i = 0; i < PenSettingsActivity.ACTIONS.length; i++) {
            keys.add(PenSettingsActivity.ACTIONS[i]);
            labels.add(getString(PenSettingsActivity.LABELS[i]));
        }
        String cur = Settings.Global.getString(getContentResolver(), "pipa_kb_super");
        int sel = Math.max(0, keys.indexOf(cur == null ? "default" : cur));
        new AlertDialog.Builder(this).setTitle(R.string.kb_super)
                .setSingleChoiceItems(labels.toArray(new String[0]), sel, (d, w) -> {
                    d.dismiss();
                    String key = keys.get(w);
                    if (PenSettingsActivity.APP.equals(key)) pickSuperApp();
                    else putSuper(key);
                })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    private void putSuper(String v) {
        try {
            Settings.Global.putString(getContentResolver(), "pipa_kb_super", v);
        } catch (SecurityException e) {
            Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
        }
    }

    private void pickSuperApp() {
        android.content.pm.PackageManager pm = getPackageManager();
        Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        java.util.TreeMap<String, String> apps = new java.util.TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        for (android.content.pm.ResolveInfo ri : pm.queryIntentActivities(main, 0)) {
            apps.put(ri.loadLabel(pm) + "\u0000" + ri.activityInfo.packageName,
                    ri.activityInfo.packageName + "/" + ri.activityInfo.name);
        }
        String[] names = new String[apps.size()], comps = new String[apps.size()];
        int i = 0;
        for (java.util.Map.Entry<String, String> e : apps.entrySet()) {
            names[i] = e.getKey().substring(0, e.getKey().indexOf('\u0000'));
            comps[i++] = e.getValue();
        }
        new AlertDialog.Builder(this).setTitle(R.string.pen_pick_app)
                .setItems(names, (d, w) -> putSuper("app:" + comps[w]))
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    // ------------------------------------------------------------------ Effects

    // helper 2.8 (user): Rich (2) and Smooth (3, stock default) only; Light (4) dropped the full-scene continuity
    private static final int[] TIERS = { 2, 3 };
    private static final int[] TIER_LABELS = { R.string.fx_tier_rich, R.string.fx_tier_smooth };
    private static final float[] SCALES = { 0f, 0.5f, 0.75f, 1f, 1.5f, 2f };
    private static final int[] SCALE_LABELS = { R.string.fx_speed_off, R.string.fx_speed_05, R.string.fx_speed_075,
            R.string.fx_speed_1, R.string.fx_speed_15, R.string.fx_speed_2 };
    private static final String[] SCALE_KEYS = { Settings.Global.WINDOW_ANIMATION_SCALE,
            Settings.Global.TRANSITION_ANIMATION_SCALE, Settings.Global.ANIMATOR_DURATION_SCALE };
    private View applyCard, rebootRow, rebootDiv;
    private final java.util.List<Runnable> fxRefresh = new java.util.ArrayList<>();

    private int sysInt(String k, int def) { return Settings.System.getInt(getContentResolver(), k, def); }

    private boolean putSys(String k, int v) {
        try {
            return Settings.System.putInt(getContentResolver(), k, v);
        } catch (RuntimeException e) {
            Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
            return false;
        }
    }

    private void needRestart() {
        if (applyCard.getVisibility() != View.VISIBLE) {
            applyCard.setVisibility(View.VISIBLE);
            applyCard.setAlpha(0f);
            applyCard.animate().alpha(1f).setDuration(250).start();
        }
    }

    /** a switch for an int setting; restart = SystemUI and the launcher read it at their start */
    private void fxToggle(LinearLayout k, String sym, int title, int sum, boolean system, String key, int onValue,
            int def, boolean restart) {
        Switch[] sw = new Switch[1];
        java.util.function.IntSupplier cur = () -> system ? sysInt(key, def)
                : Settings.Global.getInt(getContentResolver(), key, def);
        sw[0] = Ui.toggle(k, sym, getString(title), getString(sum), cur.getAsInt() == onValue, (b, on) -> {
            int v = on ? onValue : 1 - onValue;
            if (cur.getAsInt() == v) return;
            boolean ok = system ? putSys(key, v) : Status.putGlobal(this, key, v);
            if (!ok) { b.setChecked(!on); return; }
            if (restart) needRestart();
        });
        fxRefresh.add(() -> sw[0].setChecked(cur.getAsInt() == onValue));
    }

    private void effects() {
        LinearLayout col = start(R.string.m_effects);

        // shown after a change that SystemUI / the launcher read at their start
        LinearLayout ak = Ui.card(col);
        applyCard = ak;
        Ui.row(ak, "↻", getString(R.string.fx_apply), getString(R.string.fx_apply_sum), null, v -> applyFx());
        rebootDiv = new View(this);
        ak.addView(rebootDiv, new LinearLayout.LayoutParams(1, 1));
        rebootRow = Ui.row(ak, "⏻", getString(R.string.fx_reboot), getString(R.string.fx_reboot_sum), null, v -> reboot());
        rebootRow.setVisibility(View.GONE);
        ak.setVisibility(View.GONE);

        Ui.header(col, getString(R.string.fx_h_anim));
        Ui.note(col, getString(R.string.fx_anim_note));
        LinearLayout k = Ui.card(col);
        View tier = Ui.link(k, "≋", getString(R.string.fx_tier), "", v -> chooseTier());
        Ui.divider(k);
        View speed = Ui.link(k, "»", getString(R.string.fx_speed), "", v -> chooseSpeed());

        Ui.header(col, getString(R.string.fx_h_blur));
        k = Ui.card(col);
        fxToggle(k, "◍", R.string.fx_visual_blur, R.string.fx_visual_blur_sum, true, "system_material_blur_enable", 1, 1, true);
        Ui.divider(k);
        fxToggle(k, "◌", R.string.fx_glow, R.string.fx_glow_sum, true, "system_material_stroke_enable", 1, 1, true);
        Ui.divider(k);
        fxToggle(k, "✦", R.string.fx_blur, R.string.fx_blur_sum, false, "pipa_live_blur", 1, 0, true);
        Ui.divider(k);
        fxToggle(k, "▤", R.string.fx_window_blur, R.string.fx_window_blur_sum, false, "disable_window_blurs", 0, 1, false);
        Ui.divider(k);
        fxToggle(k, "≈", R.string.fx_anim_blur, R.string.fx_anim_blur_sum, true, "animationBlurrySwitch", 1, 0, true);

        k = Ui.card(col);
        Ui.row(k, "⟲", getString(R.string.fx_reset), getString(R.string.fx_reset_sum), null, v -> resetFx());
        Ui.enter(col);

        fxRefresh.add(() -> {
            int t = Settings.Global.getInt(getContentResolver(), "pipa_anim_level", 3);
            Ui.setSummary(tier, label(t, TIERS, TIER_LABELS));
            float sc = Settings.Global.getFloat(getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
            int best = 3;
            for (int i = 0; i < SCALES.length; i++) if (Math.abs(SCALES[i] - sc) < Math.abs(SCALES[best] - sc)) best = i;
            Ui.setSummary(speed, getString(SCALE_LABELS[best]));
        });
        watch(() -> { for (Runnable r : fxRefresh) r.run(); }, "pipa_anim_level", Settings.Global.ANIMATOR_DURATION_SCALE,
                "pipa_live_blur", "disable_window_blurs");
    }

    private String label(int v, int[] vals, int[] labels) {
        for (int i = 0; i < vals.length; i++) if (vals[i] == v) return getString(labels[i]);
        return String.valueOf(v);
    }

    private void chooseTier() {
        int cur = Settings.Global.getInt(getContentResolver(), "pipa_anim_level", 3), sel = 1;
        String[] items = new String[TIERS.length];
        for (int i = 0; i < TIERS.length; i++) { items[i] = getString(TIER_LABELS[i]); if (TIERS[i] == cur) sel = i; }
        new AlertDialog.Builder(this).setTitle(R.string.fx_tier)
                .setSingleChoiceItems(items, sel, (d, w) -> {
                    // the port service applies it and restarts the launcher (a few seconds)
                    if (TIERS[w] != cur && Status.putGlobal(this, "pipa_anim_level", TIERS[w])) {
                        Toast.makeText(this, R.string.fx_tier_applied, Toast.LENGTH_LONG).show();
                        needRestart();
                        rebootRow.setVisibility(View.VISIBLE);   // system_server, apps and SystemUI read it at start
                    }
                    d.dismiss();
                })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    private void chooseSpeed() {
        String[] items = new String[SCALES.length];
        for (int i = 0; i < SCALES.length; i++) items[i] = getString(SCALE_LABELS[i]);
        float sc = Settings.Global.getFloat(getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        int sel = 3;
        for (int i = 0; i < SCALES.length; i++) if (Math.abs(SCALES[i] - sc) < Math.abs(SCALES[sel] - sc)) sel = i;
        new AlertDialog.Builder(this).setTitle(R.string.fx_speed)
                .setSingleChoiceItems(items, sel, (d, w) -> { setScales(SCALES[w]); d.dismiss(); })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    private void setScales(float v) {
        try {
            for (String k : SCALE_KEYS) Settings.Global.putFloat(getContentResolver(), k, v);
        } catch (SecurityException e) {
            Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
        }
    }

    /** "uri#name" of the last logs copied into Downloads (LogsKeeper), or null */
    private String[] savedLog() {
        String v = Settings.Global.getString(getContentResolver(), LogsKeeper.KEY_URI);
        if (v == null || v.indexOf('#') < 0) return null;
        return new String[] { v.substring(0, v.indexOf('#')), v.substring(v.indexOf('#') + 1) };
    }

    private String savedLogName() {
        String[] s = savedLog();
        return s == null ? null : s[1];
    }

    private void logsRow() {
        int st = Settings.Global.getInt(getContentResolver(), "pipa_logs", 0);
        if (st == 2) {
            Toast.makeText(this, R.string.logs_running, Toast.LENGTH_SHORT).show();
            return;
        }
        String[] saved = savedLog();
        AlertDialog.Builder b = new AlertDialog.Builder(this).setTitle(R.string.logs_collect)
                .setMessage(R.string.logs_confirm)
                .setPositiveButton(R.string.logs_do, (d, w) -> {
                    if (!Status.putGlobal(this, "pipa_logs", 1))
                        Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
                })
                .setNegativeButton(android.R.string.cancel, null);
        if (saved != null) b.setNeutralButton(R.string.logs_share_last,
                (d, w) -> go(LogsKeeper.shareIntent(this, Uri.parse(saved[0]))));
        b.show();
    }

    private void optimiseApps() {
        int st = Settings.Global.getInt(getContentResolver(), "pipa_dexopt", 0);
        if (st == 2) {   // 1 = request not taken yet (service busy or off): asking again is harmless
            Toast.makeText(this, R.string.sys_opt_running, Toast.LENGTH_SHORT).show();
            return;
        }
        new AlertDialog.Builder(this).setTitle(R.string.sys_opt).setMessage(R.string.sys_opt_confirm)
                .setPositiveButton(R.string.sys_opt_do, (d, w) -> {
                    if (!Status.putGlobal(this, "pipa_dexopt", 1))
                        Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
                })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    private void reboot() {
        try {
            getSystemService(android.os.PowerManager.class).reboot(null);
        } catch (SecurityException e) {
            Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
        }
    }

    private void applyFx() {
        if (Status.putGlobal(this, "pipa_fx_restart", 1)) {
            Toast.makeText(this, R.string.fx_applying, Toast.LENGTH_LONG).show();
            applyCard.setVisibility(View.GONE);
        }
    }

    /** the values the port ships with (service.sh first-boot defaults, 5t / beta7.1) */
    private void resetFx() {
        new AlertDialog.Builder(this).setTitle(R.string.fx_reset).setMessage(R.string.fx_reset_confirm)
                .setPositiveButton(R.string.fx_reset_do, (d, w) -> {
                    Status.putGlobal(this, "pipa_anim_level", 3);
                    setScales(1f);
                    putSys("system_material_blur_enable", 1);
                    putSys("system_material_stroke_enable", 1);
                    putSys("animationBlurrySwitch", 0);
                    Status.putGlobal(this, "pipa_live_blur", 0);
                    Status.putGlobal(this, "disable_window_blurs", 1);
                    for (Runnable r : fxRefresh) r.run();
                    // 8s (user): no automatic restart; Apply (status bar + home screen) or Reboot (everywhere)
                    needRestart();
                    rebootRow.setVisibility(View.VISIBLE);
                    Toast.makeText(this, R.string.fx_reset_done, Toast.LENGTH_LONG).show();
                })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    // ------------------------------------------------------------------ Games

    private static final int[] SCENES = { 20, 13, 10, 0 };
    private static final int[] SCENE_LABELS = { R.string.game_scene_20, R.string.game_scene_13, R.string.game_scene_10,
            R.string.game_scene_off };
    private LinearLayout gameCard;

    private void games() {
        LinearLayout col = start(R.string.m_games);
        LinearLayout k = Ui.card(col);
        View prof = Ui.link(k, "◆", getString(R.string.game_profile), "", v -> chooseScene());
        Ui.note(k, getString(R.string.game_note));

        Ui.header(col, getString(R.string.gid_h));
        Ui.note(col, getString(R.string.gid_note));
        gameCard = Ui.card(col);
        fillGames();
        Ui.enter(col);
        watch(() -> {
            int sc = Settings.Global.getInt(getContentResolver(), "pipa_game_scene", 20);
            boolean fg = Status.global(this, "pipa_game_fg", 0);
            String now = sc == 0 ? "" : " · " + getString(fg ? R.string.game_active : R.string.game_idle);
            Ui.setSummary(prof, label(sc, SCENES, SCENE_LABELS) + now);
        }, "pipa_game_fg", "pipa_game_scene");
    }

    private void chooseScene() {
        int cur = Settings.Global.getInt(getContentResolver(), "pipa_game_scene", 20), sel = 0;
        String[] items = new String[SCENES.length];
        for (int i = 0; i < SCENES.length; i++) { items[i] = getString(SCENE_LABELS[i]); if (SCENES[i] == cur) sel = i; }
        new AlertDialog.Builder(this).setTitle(R.string.game_profile)
                .setSingleChoiceItems(items, sel, (d, w) -> { Status.putGlobal(this, "pipa_game_scene", SCENES[w]); d.dismiss(); })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    /** Global pipa_app_identity as an ordered map pkg -> key */
    private java.util.LinkedHashMap<String, String> choices() {
        java.util.LinkedHashMap<String, String> m = new java.util.LinkedHashMap<>();
        String v = Settings.Global.getString(getContentResolver(), GameIdentity.KEY);
        if (v != null) for (String e : v.split(";")) {
            int i = e.indexOf('=');
            if (i > 0) m.put(e.substring(0, i), e.substring(i + 1));
        }
        return m;
    }

    private void saveChoices(java.util.Map<String, String> m) {
        StringBuilder sb = new StringBuilder();
        for (java.util.Map.Entry<String, String> e : m.entrySet()) {
            if (sb.length() > 0) sb.append(';');
            sb.append(e.getKey()).append('=').append(e.getValue());
        }
        try {
            Settings.Global.putString(getContentResolver(), GameIdentity.KEY, sb.length() == 0 ? null : sb.toString());
        } catch (SecurityException e) {
            Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
        }
    }

    /** every launchable user app; apps with another identity (choice or port default) first */
    private void fillGames() {
        gameCard.removeAllViews();
        android.content.pm.PackageManager pm = getPackageManager();
        java.util.Map<String, String> ch = choices();
        java.util.TreeMap<String, android.content.pm.ApplicationInfo> spoofed =
                new java.util.TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        java.util.TreeMap<String, android.content.pm.ApplicationInfo> real =
                new java.util.TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        for (android.content.pm.ResolveInfo ri : pm.queryIntentActivities(main, 0)) {
            android.content.pm.ApplicationInfo ai = ri.activityInfo.applicationInfo;
            if ((ai.flags & android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0) continue;
            String pkg = ai.packageName, c = ch.get(pkg);
            boolean other = c != null ? !"real".equals(c) : GameIdentity.defaultFor(pkg) != null;
            (other ? spoofed : real).put(ai.loadLabel(pm) + "\u0000" + pkg, ai);
        }
        boolean first = true;
        for (java.util.Map<String, android.content.pm.ApplicationInfo> part : java.util.List.of(spoofed, real)) {
            for (android.content.pm.ApplicationInfo ai : part.values()) {
                if (!first) Ui.divider(gameCard);
                first = false;
                String pkg = ai.packageName;
                View r = Ui.link(gameCard, null, ai.loadLabel(pm), appSummary(ai, ch.get(pkg)), v -> appOptions(ai));
                android.widget.ImageView icon = new android.widget.ImageView(this);
                icon.setImageDrawable(ai.loadIcon(pm));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(Ui.px(this, 38), Ui.px(this, 38));
                lp.rightMargin = Ui.px(this, 14);
                ((LinearLayout) r).addView(icon, 0, lp);
            }
        }
    }

    private java.util.LinkedHashSet<String> manualGames() {
        java.util.LinkedHashSet<String> m = new java.util.LinkedHashSet<>();
        String v = Settings.Global.getString(getContentResolver(), GameKeeper.MANUAL);
        if (v != null) for (String p : v.split(",")) if (!p.isEmpty()) m.add(p);
        return m;
    }

    private static boolean autoGame(android.content.pm.ApplicationInfo ai) {
        return ai.category == android.content.pm.ApplicationInfo.CATEGORY_GAME
                || (ai.flags & android.content.pm.ApplicationInfo.FLAG_IS_GAME) != 0;
    }

    private String appSummary(android.content.pm.ApplicationInfo ai, String choice) {
        String s = identitySummary(ai.packageName, choice);
        if (autoGame(ai)) return s + " · " + getString(R.string.gid_game_auto);
        if (manualGames().contains(ai.packageName)) return s + " · " + getString(R.string.gid_game_manual);
        return s;
    }

    /** per app: device identity, and "treat as a game" (performance profile) */
    private void appOptions(android.content.pm.ApplicationInfo ai) {
        String pkg = ai.packageName;
        boolean auto = autoGame(ai);
        java.util.LinkedHashSet<String> mg = manualGames();
        boolean manual = mg.contains(pkg);
        String[] items = {
            getString(R.string.gid_opt_identity, identitySummary(pkg, choices().get(pkg))),
            auto ? getString(R.string.gid_opt_game_auto)
                 : getString(manual ? R.string.gid_opt_game_remove : R.string.gid_opt_game_add)
        };
        new AlertDialog.Builder(this).setTitle(ai.loadLabel(getPackageManager()))
                .setItems(items, (d, w) -> {
                    if (w == 0) { chooseIdentity(pkg); return; }
                    if (auto) return;
                    if (manual) mg.remove(pkg); else mg.add(pkg);
                    try {
                        Settings.Global.putString(getContentResolver(), GameKeeper.MANUAL,
                                mg.isEmpty() ? null : String.join(",", mg));
                    } catch (SecurityException e) {
                        Toast.makeText(this, R.string.pen_no_perm, Toast.LENGTH_LONG).show();
                    }
                    fillGames();
                })
                .setNegativeButton(android.R.string.cancel, null).show();
    }

    private String identitySummary(String pkg, String choice) {
        String def = GameIdentity.defaultFor(pkg);
        if (choice == null) return def == null ? getString(R.string.gid_real_default)
                : getString(R.string.gid_port_default, GameIdentity.label(def));
        if ("real".equals(choice)) return getString(R.string.gid_real);
        return GameIdentity.label(choice);
    }

    private void chooseIdentity(String pkg) {
        String def = GameIdentity.defaultFor(pkg);
        java.util.List<String> keys = new java.util.ArrayList<>();
        java.util.List<String> labels = new java.util.ArrayList<>();
        keys.add(null);
        labels.add(def == null ? getString(R.string.gid_real_default) : getString(R.string.gid_port_default, GameIdentity.label(def)));
        if (def != null) { keys.add("real"); labels.add(getString(R.string.gid_real)); }
        for (String[] p : GameIdentity.PROFILES) { keys.add(p[0]); labels.add(p[1]); }
        java.util.LinkedHashMap<String, String> ch = choices();
        int sel = Math.max(0, keys.indexOf(ch.get(pkg)));
        new AlertDialog.Builder(this)
                .setTitle(R.string.gid_choose)
                .setSingleChoiceItems(labels.toArray(new String[0]), sel, (d, which) -> {
                    String key = keys.get(which);
                    if (key == null) ch.remove(pkg); else ch.put(pkg, key);
                    saveChoices(ch);
                    // the app reads its identity at start: end its background process so the next start uses it
                    getSystemService(android.app.ActivityManager.class).killBackgroundProcesses(pkg);
                    Toast.makeText(this, R.string.gid_applied, Toast.LENGTH_SHORT).show();
                    d.dismiss();
                    fillGames();
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    // ------------------------------------------------------------------ System

    private void system() {
        LinearLayout col = start(R.string.m_system);
        LinearLayout k = Ui.card(col);
        globalToggle(k, "☰", R.string.sys_logs, R.string.sys_logs_sum, "pipa_verbose_logs", 0);

        // 8n: global pipa_dexopt 1 = request, 2 = running (pipa_port service: pm bg-dexopt-job), 0 = idle
        k = Ui.card(col);
        View opt = Ui.row(k, "⚡", getString(R.string.sys_opt), "", null, v -> optimiseApps());
        Runnable optSum = () -> {
            int st = Settings.Global.getInt(getContentResolver(), "pipa_dexopt", 0);
            if (st == 1 || st == 2) {
                Ui.setSummary(opt, getString(R.string.sys_opt_running));
                return;
            }
            long last = Settings.Global.getLong(getContentResolver(), "pipa_dexopt_last", 0);
            String sum = getString(R.string.sys_opt_sum);
            if (last > 0) sum += "\n" + getString(R.string.sys_opt_last,
                    android.text.format.DateFormat.getMediumDateFormat(this).format(new java.util.Date(last * 1000))
                    + " " + android.text.format.DateFormat.getTimeFormat(this).format(new java.util.Date(last * 1000)));
            Ui.setSummary(opt, sum);
        };

        // 8q: bug report logs (pipa_logs 1 = request, 2 = running; LogsKeeper copies the file into Downloads)
        Ui.header(col, getString(R.string.sys_h_report));
        k = Ui.card(col);
        View logs = Ui.row(k, "⇩", getString(R.string.logs_collect), "", null, v -> logsRow());
        Ui.divider(k);
        Ui.link(k, "✉", getString(R.string.sys_bug), getString(R.string.sys_bug_sum),
                v -> go(new Intent(Intent.ACTION_VIEW, Uri.parse(REPO_ISSUES))));
        Runnable logsSum = () -> {
            int st = Settings.Global.getInt(getContentResolver(), "pipa_logs", 0);
            if (st == 1 || st == 2) {
                Ui.setSummary(logs, getString(R.string.logs_running));
                return;
            }
            String saved = savedLogName();
            Ui.setSummary(logs, saved == null ? getString(R.string.logs_collect_sum)
                    : getString(R.string.logs_collect_sum) + "\n" + getString(R.string.logs_last, saved));
        };
        watch(() -> { optSum.run(); logsSum.run(); },
                "pipa_dexopt", "pipa_dexopt_last", "pipa_logs", LogsKeeper.KEY_URI);

        Ui.header(col, getString(R.string.sys_h_about));
        k = Ui.card(col);
        String build = Status.build();
        Ui.row(k, null, getString(R.string.sys_build), build.isEmpty() ? "–" : build, null, null);
        Ui.divider(k);
        Ui.row(k, null, getString(R.string.sys_rom), Status.rom(), null, null);
        Ui.divider(k);
        String ver;
        try {
            ver = getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            ver = "?";
        }
        Ui.row(k, null, getString(R.string.app_name), ver, null, null);
        Ui.enter(col);
    }
}
