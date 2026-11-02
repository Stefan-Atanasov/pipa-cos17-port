package com.port.pipa.helper;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;

import java.lang.reflect.Method;

/**
 * BUGS-TODO 49: Circle to Search from a long press of the gesture bar.
 *
 * ColorOS CN has no call to ContextualSearchManager (the global SystemUI/launcher have it), and Android 17 no longer
 * starts Circle to Search through the assistant session (flag disable_starting_contextual_search_via_vims). With the
 * helper as the default assistant, SystemUI starts this ACTION_ASSIST activity on the long press; it asks the
 * contextual_search service (needs ACCESS_CONTEXTUAL_SEARCH, privileged) to start Circle to Search and closes.
 * ContextualSearchManager is a system API, reached by reflection.
 */
public class CircleSearchActivity extends Activity {
    private static final String TAG = "PipaHelper.CTS";
    private static final int ENTRYPOINT_LONG_PRESS_NAV_HANDLE = 2;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        try {
            Object csm = getSystemService("contextual_search");
            Method m = csm.getClass().getMethod("startContextualSearch", int.class);
            m.invoke(csm, ENTRYPOINT_LONG_PRESS_NAV_HANDLE);
            Log.i(TAG, "Circle to Search started");
        } catch (ReflectiveOperationException | RuntimeException e) {
            Throwable c = e.getCause() != null ? e.getCause() : e;
            Log.w(TAG, "start failed: " + c);
        }
        finish();
        overridePendingTransition(0, 0);
    }
}
