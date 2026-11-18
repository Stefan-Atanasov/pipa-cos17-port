package com.port.pipa.helper;

import android.service.voice.VoiceInteractionService;
import android.service.voice.VoiceInteractionSession;
import android.util.Log;

/**
 * Helper 2.0 (BUGS-TODO 49/98, user 2026-11-18): the helper is a real assistant (VoiceInteractionService) instead of an
 * invisible ACTION_ASSIST activity. The session routes by invocation type: gesture-bar long press -> Circle to Search,
 * corner swipe -> Gemini. No hotword, no microphone: the service is bound by the system and idle until a gesture.
 */
public class AssistService extends VoiceInteractionService {
    static final String TAG = "PipaHelper.Assist";

    @Override
    public void onReady() {
        super.onReady();
        // no assist structure, no screenshot: the session only starts other apps (saves the capture work)
        setDisabledShowContext(VoiceInteractionSession.SHOW_WITH_ASSIST | VoiceInteractionSession.SHOW_WITH_SCREENSHOT);
        Log.i(TAG, "assistant service ready");
    }
}
