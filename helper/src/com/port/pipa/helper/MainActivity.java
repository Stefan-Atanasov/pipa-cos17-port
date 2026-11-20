package com.port.pipa.helper;

import android.app.Activity;
import android.content.Intent;
import android.database.ContentObserver;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.hardware.input.InputManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * helper 2.5: home of the Pipa Helper app. A status card (device, port build, kernel, pen, keyboard case) and the
 * menus. The status updates live while the screen is visible (a settings observer and an input-device listener, no
 * polling) and stops in onPause.
 */
public final class MainActivity extends Activity {
    private TextView penPill, kbPill;
    private View penRow;
    private final Handler h = new Handler(Looper.getMainLooper());
    private final ContentObserver penObs = new ContentObserver(h) {
        @Override public void onChange(boolean self) { refresh(); }
    };
    private final InputManager.InputDeviceListener kbListener = new InputManager.InputDeviceListener() {
        @Override public void onInputDeviceAdded(int id) { refresh(); }
        @Override public void onInputDeviceRemoved(int id) { refresh(); }
        @Override public void onInputDeviceChanged(int id) { refresh(); }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout col = Ui.page(this, getString(R.string.app_name), false);
        col.addView(hero());

        LinearLayout k = Ui.card(col);
        penRow = Ui.link(k, "✎", getString(R.string.m_pen), getString(R.string.m_pen_sum), v -> open("pen"));
        Ui.divider(k);
        Ui.link(k, "⌨", getString(R.string.m_keyboard), getString(R.string.m_keyboard_sum), v -> open("keyboard"));

        k = Ui.card(col);
        Ui.link(k, "✦", getString(R.string.m_effects), getString(R.string.m_effects_sum), v -> open("effects"));
        Ui.divider(k);
        Ui.link(k, "◆", getString(R.string.m_games), getString(R.string.m_games_sum), v -> open("games"));

        k = Ui.card(col);
        Ui.link(k, "⚙", getString(R.string.m_system), getString(R.string.m_system_sum), v -> open("system"));
        Ui.enter(col);
    }

    private void open(String page) {
        Ui.open(this, new Intent(this, PageActivity.class).putExtra(PageActivity.EXTRA_PAGE, page));
    }

    /** the status card at the top */
    private View hero() {
        LinearLayout k = new LinearLayout(this);
        k.setOrientation(LinearLayout.VERTICAL);
        int p = Ui.px(this, 20);
        k.setPadding(p, p, p, p);
        GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[] { Ui.accentSoft(this), Ui.card(this) });
        d.setCornerRadius(Ui.px(this, 24));
        k.setBackground(d);

        TextView dev = new TextView(this);
        dev.setText(R.string.hero_device);
        dev.setTextSize(22);
        dev.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        dev.setTextColor(Ui.text(this));
        k.addView(dev);

        String build = Status.build();
        TextView rom = new TextView(this);
        rom.setText(build.isEmpty() ? getString(R.string.hero_rom) : getString(R.string.hero_rom_build, build));
        rom.setTextSize(14);
        rom.setTextColor(Ui.sub(this));
        rom.setPadding(0, Ui.px(this, 4), 0, 0);
        k.addView(rom);


        LinearLayout pills = new LinearLayout(this);
        pills.setOrientation(LinearLayout.HORIZONTAL);
        pills.setPadding(0, Ui.px(this, 14), 0, 0);
        penPill = pill();
        kbPill = pill();
        pills.addView(penPill);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.px(this, 8);
        pills.addView(kbPill, lp);
        k.addView(pills);

        LinearLayout.LayoutParams kl = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        kl.topMargin = Ui.px(this, 4);
        k.setLayoutParams(kl);
        return k;
    }

    private TextView pill() {
        TextView t = new TextView(this);
        t.setTextSize(13);
        t.setGravity(Gravity.CENTER_VERTICAL);
        t.setPadding(Ui.px(this, 12), Ui.px(this, 6), Ui.px(this, 12), Ui.px(this, 6));
        return t;
    }

    private void setPill(TextView t, String s, boolean on) {
        t.setText(s);
        GradientDrawable d = new GradientDrawable();
        d.setCornerRadius(Ui.px(this, 16));
        d.setColor(on ? Ui.accent(this) : (Ui.night(this) ? 0x33FFFFFF : 0x14000000));
        t.setBackground(d);
        t.setTextColor(on ? (Ui.night(this) ? 0xFF000000 : 0xFFFFFFFF) : Ui.sub(this));
    }

    private void refresh() {
        boolean pen = Status.penConnected(this);
        int bat = Status.penBattery(this);
        String ps = pen ? (bat >= 0 ? getString(R.string.hero_pen_bat, bat) : getString(R.string.hero_pen_on))
                : getString(R.string.hero_pen_off);
        setPill(penPill, "✎  " + ps, pen);
        boolean kb = Status.keyboard(this);
        setPill(kbPill, "⌨  " + getString(kb ? R.string.hero_kb_on : R.string.hero_kb_off), kb);
        Ui.setSummary(penRow, pen && bat >= 0 ? getString(R.string.m_pen_sum_bat, bat) : getString(R.string.m_pen_sum));
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
        getContentResolver().registerContentObserver(Settings.Global.getUriFor("ipe_pencil_connect_state"), false, penObs);
        getContentResolver().registerContentObserver(Settings.Global.getUriFor("ipe_pencil_battery_level"), false, penObs);
        getSystemService(InputManager.class).registerInputDeviceListener(kbListener, h);
    }

    @Override
    protected void onPause() {
        getContentResolver().unregisterContentObserver(penObs);
        getSystemService(InputManager.class).unregisterInputDeviceListener(kbListener);
        super.onPause();
    }
}
