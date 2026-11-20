package com.port.pipa.helper;

import android.app.Application;

/** Entry point: the persistent process starts here at boot. Each feature is a small keeper. */
public final class HelperApp extends Application {
    private DolbyKeeper dolby;
    private PenKeeper pen;
    private LidKeeper lid;
    private GameKeeper game;
    private LogsKeeper logs;

    @Override
    public void onCreate() {
        super.onCreate();
        // the settings UI (Pipa Helper app, 2.5) runs in its own process ":ui": a crash there cannot stop the keepers
        if (!getPackageName().equals(Application.getProcessName())) return;
        PenActionReceiver.init(this);
        dolby = new DolbyKeeper(this);
        dolby.start();
        pen = new PenKeeper(this);
        pen.start();
        lid = new LidKeeper(this);
        lid.start();
        game = new GameKeeper(this);
        game.start();
        logs = new LogsKeeper(this);
        logs.start();
    }
}
