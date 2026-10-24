package com.port.pipa.helper;

import android.app.Application;

/** Entry point: the persistent process starts here at boot. Each feature is a small keeper. */
public final class HelperApp extends Application {
    private DolbyKeeper dolby;
    private PenKeeper pen;
    private LidKeeper lid;

    @Override
    public void onCreate() {
        super.onCreate();
        dolby = new DolbyKeeper(this);
        dolby.start();
        pen = new PenKeeper(this);
        pen.start();
        lid = new LidKeeper(this);
        lid.start();
    }
}
