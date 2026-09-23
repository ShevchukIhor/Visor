package com.visor.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-schedules the daily reminder after a device reboot, because AlarmManager
 * alarms are cleared on boot. Reads the stored (enabled/hour/minute) and
 * re-arms the exact alarm for the next occurrence.
 *
 * QUICKBOOT_POWERON (and its HTC spelling) is handled too: several OEM skins
 * use a fast-boot path that never broadcasts BOOT_COMPLETED.
 */
class BootReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent?) {
    val action = intent?.action ?: return
    if (action !in BOOT_ACTIONS) return
    ReminderScheduler.scheduleNextDay(context)
  }

  private companion object {
    val BOOT_ACTIONS = setOf(
      Intent.ACTION_BOOT_COMPLETED,
      Intent.ACTION_MY_PACKAGE_REPLACED,
      "android.intent.action.QUICKBOOT_POWERON",
      "com.htc.intent.action.QUICKBOOT_POWERON",
    )
  }
}
