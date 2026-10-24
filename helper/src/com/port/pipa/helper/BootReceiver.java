package com.port.pipa.helper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Only wakes the process; HelperApp.onCreate starts the keepers. */
public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
    }
}
