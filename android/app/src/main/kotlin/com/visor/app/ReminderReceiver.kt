package com.visor.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Fired by AlarmManager at the user's chosen daily time. Checks whether the
 * user trained today (via [ReminderStore]) and only posts a notification if
 * they have NOT — so reminders never nag after a completed workout.
 *
 * Reschedules itself for the next day after firing (exact alarms are
 * one-shot), so the daily cadence continues without the app being opened.
 *
 * [ACTION_TEST] is a separate action (and a separate PendingIntent slot) so
 * firing a test notification never disturbs the armed daily alarm.
 */
class ReminderReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent?) {
    when (intent?.action) {
      ACTION_REMINDER -> {
        handleReminder(context)
        ReminderScheduler.scheduleNextDay(context)
      }
      ACTION_TEST -> {
        // A test fires unconditionally — the point is to verify the pipeline,
        // not to respect the "already trained" rule. It also must NOT
        // reschedule anything: the daily alarm is a different PendingIntent.
        showNotification(
          context,
          "Visor test notification",
          "Notifications are working. Your daily reminder is unaffected.",
        )
      }
    }
  }

  private fun handleReminder(context: Context) {
    if (ReminderStore.trainedToday(context)) return
    showNotification(
      context,
      "Keep your streak alive",
      "You haven't trained today — 1 minute keeps your streak going.",
    )
  }

  private fun showNotification(context: Context, title: String, text: String) {
    val channelId = "visor_reminder"
    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
        as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        channelId,
        "Training reminders",
        NotificationManager.IMPORTANCE_DEFAULT,
      )
      nm.createNotificationChannel(channel)
    }

    val tapIntent = context.packageManager.getLaunchIntentForPackage(
        context.packageName,
      ) ?: Intent()
    val contentPi = PendingIntent.getActivity(
      context,
      0,
      tapIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(context, channelId)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(context)
    }

    val notification = builder
      .setSmallIcon(R.drawable.ic_notification)
      .setContentTitle(title)
      .setContentText(text)
      .setContentIntent(contentPi)
      .setAutoCancel(true)
      .build()

    try {
      nm.notify(NOTIFICATION_ID, notification)
    } catch (_: SecurityException) {
      // POST_NOTIFICATIONS not granted (API 33+) — silently skip.
    }
  }

  companion object {
    const val ACTION_REMINDER = "com.visor.app.ACTION_REMINDER"
    const val ACTION_TEST = "com.visor.app.ACTION_TEST"
    private const val NOTIFICATION_ID = 1001
  }
}
