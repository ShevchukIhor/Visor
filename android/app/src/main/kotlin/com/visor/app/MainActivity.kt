package com.visor.app

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * Visor host activity. Exposes three MethodChannels:
 *  - "visor/reminder" — daily training reminder via AlarmManager (exact).
 *  - "visor/wallet"   — Seed Vault (MWA) authorize.
 *  - "visor/notify"   — request POST_NOTIFICATIONS permission + test fire.
 *
 * Uses FlutterFragmentActivity (a ComponentActivity) because the Mobile Wallet
 * Adapter clientlib requires ComponentActivity for ActivityResultSender.
 */
class MainActivity : FlutterFragmentActivity() {

  private val REMINDER_CHANNEL = "visor/reminder"
  private val WALLET_CHANNEL = "visor/wallet"
  private val NOTIFY_CHANNEL = "visor/notify"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    WalletConnect.attach(this)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDER_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "scheduleReminder" -> {
            val enabled = (call.argument<Boolean>("enabled")) ?: false
            val hour = (call.argument<Int>("hour")) ?: 21
            val minute = (call.argument<Int>("minute")) ?: 0
            result.success(ReminderScheduler.schedule(this, enabled, hour, minute))
          }
          "hasSchedule" -> {
            result.success(ReminderScheduler.hasSchedule(this))
          }
          "markTrained" -> {
            val ts = (call.argument<Number>("ts"))?.toLong()
                ?: System.currentTimeMillis()
            ReminderStore.markTrained(this, ts)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WALLET_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "authorizeWallet" -> WalletConnect.authorize(this, result)
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFY_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "hasNotificationPermission" -> {
            result.success(hasNotificationPermission())
          }
          "requestNotificationPermission" -> {
            requestNotificationPermission()
            result.success(null)
          }
          "testNotify" -> {
            result.success(ReminderScheduler.scheduleTest(this, 5))
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun hasNotificationPermission(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
          PackageManager.PERMISSION_GRANTED
    }
    return true
  }

  private fun requestNotificationPermission() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2001)
    }
  }
}

/**
 * Centralized alarm scheduling. Exact one-shot alarms + self-rescheduling so
 * the daily reminder fires reliably (even in Doze) and survives reboots via
 * [BootReceiver].
 */
object ReminderScheduler {

  private const val REQ_REMINDER = 1001

  fun schedule(context: Context, enabled: Boolean, hour: Int, minute: Int): Boolean {
    store(context).edit()
      .putBoolean("enabled", enabled)
      .putInt("hour", hour)
      .putInt("minute", minute)
      .apply()

    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, REQ_REMINDER, ReminderReceiver.ACTION_REMINDER)

    if (!enabled) {
      am.cancel(pi)
      return true
    }

    return scheduleExact(am, pi, nextTriggerMillis(hour, minute))
  }

  fun hasSchedule(context: Context): Boolean {
    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, REQ_REMINDER, ReminderReceiver.ACTION_REMINDER, noCreate = true)
    return pi != null
  }

  /** One-shot exact-fire test: reminds in [seconds] seconds regardless of time. */
  fun scheduleTest(context: Context, seconds: Long): Boolean {
    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, REQ_REMINDER, ReminderReceiver.ACTION_REMINDER)
    return scheduleExact(am, pi, System.currentTimeMillis() + seconds * 1000)
  }

  fun scheduleNextDay(context: Context) {
    val sp = store(context)
    if (!sp.getBoolean("enabled", false)) return
    val hour = sp.getInt("hour", 21)
    val minute = sp.getInt("minute", 0)
    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, REQ_REMINDER, ReminderReceiver.ACTION_REMINDER)
    scheduleExact(am, pi, nextTriggerMillis(hour, minute))
  }

  private fun scheduleExact(
    am: AlarmManager,
    pi: PendingIntent,
    triggerAt: Long,
  ): Boolean {
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
      } else {
        @Suppress("DEPRECATION")
        am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
      }
      true
    } catch (e: SecurityException) {
      // SCHEDULE_EXACT_ALARM not granted on Android 12+ — fall back to inexact.
      try {
        am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        true
      } catch (_: Exception) {
        false
      }
    }
  }

  private fun nextTriggerMillis(hour: Int, minute: Int): Long {
    val now = Calendar.getInstance()
    val next = Calendar.getInstance().apply {
      set(Calendar.HOUR_OF_DAY, hour)
      set(Calendar.MINUTE, minute)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    if (next.timeInMillis <= now.timeInMillis) {
      next.add(Calendar.DAY_OF_MONTH, 1)
    }
    return next.timeInMillis
  }

  private fun pendingIntent(
    context: Context,
    req: Int,
    action: String,
    noCreate: Boolean = false,
  ): PendingIntent {
    val intent = Intent(context, ReminderReceiver::class.java).apply {
      this.action = action
    }
    val flags = if (noCreate) {
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE
    } else {
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }
    return PendingIntent.getBroadcast(context, req, intent, flags)
  }

  private fun store(context: Context) =
    context.getSharedPreferences("visor_reminder", Context.MODE_PRIVATE)
}