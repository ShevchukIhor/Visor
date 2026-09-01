package com.visor.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-schedules the daily reminder after a device reboot, because AlarmManager
 * alarms are cleared on boot. Reads the stored (enabled/hour/minute) and
 * re-arms the exact alarm for the next occurrence.
 */
class BootReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent?) {
    if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
        intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) {
      return
    }
    ReminderScheduler.scheduleNextDay(context)
  }
}