package com.port.pipa.helper;

import android.content.Intent;
import android.os.RemoteException;
import android.speech.RecognitionService;
import android.speech.SpeechRecognizer;

/**
 * An assistant service must name a RecognitionService (VoiceInteractionServiceInfo). The helper does no speech
 * recognition: every request ends with ERROR_CLIENT at once. The system default recognizer
 * (Settings.Secure voice_recognition_service) is not changed by the assistant role (it was unset before helper 2.0).
 */
public class NoRecognitionService extends RecognitionService {
    @Override
    protected void onStartListening(Intent recognizerIntent, Callback listener) {
        try {
            listener.error(SpeechRecognizer.ERROR_CLIENT);
        } catch (RemoteException ignored) {
        }
    }

    @Override
    protected void onCancel(Callback listener) {
    }

    @Override
    protected void onStopListening(Callback listener) {
    }
}
