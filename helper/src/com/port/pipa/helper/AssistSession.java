package com.port.pipa.helper;

import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.service.voice.VoiceInteractionSession;
import android.util.Log;

import java.lang.reflect.Method;

/**
 * Routes one assistant invocation and closes at once (no UI).
 * invocation_type (AssistManager.INVOCATION_TYPE_KEY): 1 = gesture (corner swipe) -> Gemini app, else (OplusLauncher
 * nav-handle long press = 1000, AOSP 8) -> Circle to Search through the contextual_search service
 * (ACCESS_CONTEXTUAL_SEARCH, privileged; ContextualSearchManager is a system API, reached by reflection).
 */
public class AssistSession extends VoiceInteractionSession {
    private static final String TAG = AssistService.TAG;
    private static final int INVOCATION_TYPE_GESTURE = 1;
    private static final int ENTRYPOINT_LONG_PRESS_NAV_HANDLE = 2;
    private static final ComponentName GEMINI =
            new ComponentName("com.google.android.apps.bard", "com.google.android.apps.bard.shellapp.BardEntryPointActivity");
    private static final ComponentName GOOGLE_VOICE =
            new ComponentName("com.google.android.googlequicksearchbox",
                    "com.google.android.googlequicksearchbox.GoogleAppVoiceAssistEntrypoint");

    AssistSession(Context c) {
        super(c);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        setUiEnabled(false);
    }

    @Override
    public void onShow(Bundle args, int showFlags) {
        super.onShow(args, showFlags);
        int type = args == null ? -1 : args.getInt("invocation_type", -1);
        Log.i(TAG, "invocation_type=" + type + " flags=" + showFlags);
        if (type == INVOCATION_TYPE_GESTURE) {
            if (!start(new Intent(Intent.ACTION_MAIN).setComponent(GEMINI))
                    && !start(new Intent("android.intent.action.VOICE_ASSIST").setComponent(GOOGLE_VOICE))) {
                startCircleToSearch();
            }
        } else {
            startCircleToSearch();
        }
        hide();
    }

    private boolean start(Intent i) {
        try {
            getContext().startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Log.i(TAG, "started " + i.getComponent().flattenToShortString());
            return true;
        } catch (ActivityNotFoundException | SecurityException e) {
            Log.w(TAG, "start " + i.getComponent().flattenToShortString() + " failed: " + e);
            return false;
        }
    }

    private void startCircleToSearch() {
        try {
            Object csm = getContext().getSystemService("contextual_search");
            Method m = csm.getClass().getMethod("startContextualSearch", int.class);
            m.invoke(csm, ENTRYPOINT_LONG_PRESS_NAV_HANDLE);
            Log.i(TAG, "Circle to Search started");
        } catch (ReflectiveOperationException | RuntimeException e) {
            Throwable c = e.getCause() != null ? e.getCause() : e;
            Log.w(TAG, "Circle to Search failed: " + c);
        }
    }
}
