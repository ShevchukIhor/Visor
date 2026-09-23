package com.visor.app

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * Visor host activity. Exposes four MethodChannels:
 *  - "visor/reminder" — daily training reminder via AlarmManager (exact).
 *  - "visor/wallet"   — Seed Vault (MWA) tipping.
 *  - "visor/notify"   — notification + exact-alarm permission plumbing.
 *  - "visor/app"      — app metadata (version), so the UI never hardcodes it.
 *
 * Uses FlutterFragmentActivity (a ComponentActivity) because the Mobile Wallet
 * Adapter clientlib requires ComponentActivity for ActivityResultSender.
 */
class MainActivity : FlutterFragmentActivity() {

  private val REMINDER_CHANNEL = "visor/reminder"
  private val WALLET_CHANNEL = "visor/wallet"
  private val NOTIFY_CHANNEL = "visor/notify"
  private val APP_CHANNEL = "visor/app"

  /** In-flight POST_NOTIFICATIONS request; answered in onRequestPermissionsResult. */
  private var pendingPermissionResult: MethodChannel.Result? = null

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
          // Single source of truth for the recipient address and the minimum
          // tip amounts — the Dart UI renders whatever this returns instead
          // of keeping its own copy that can drift.
          "tipConfig" -> result.success(WalletConnect.tipConfig())
          "sendTip" -> {
            val token = (call.argument<String>("token")) ?: "SOL"
            val amount = (call.argument<Number>("amount"))?.toDouble() ?: 0.0
            WalletConnect.sendTip(this, token, amount, result)
          }
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFY_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "hasNotificationPermission" -> {
            result.success(hasNotificationPermission())
          }
          // Answers only after the user dismisses the system dialog, so the
          // caller never reads the pre-dialog value.
          "requestNotificationPermission" -> requestNotificationPermission(result)
          "testNotify" -> {
            result.success(ReminderScheduler.scheduleTest(this, 5))
          }
          "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
          "openExactAlarmSettings" -> {
            openExactAlarmSettings()
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "appVersion" -> result.success(appVersion())
          else -> result.notImplemented()
        }
      }
  }

  override fun onDestroy() {
    // Drop the cached ActivityResultSender so it never outlives this Activity.
    WalletConnect.detach(this)
    pendingPermissionResult?.success(hasNotificationPermission())
    pendingPermissionResult = null
    super.onDestroy()
  }

  private fun appVersion(): String = try {
    packageManager.getPackageInfo(packageName, 0).versionName ?: ""
  } catch (_: PackageManager.NameNotFoundException) {
    ""
  }

  private fun hasNotificationPermission(): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
          PackageManager.PERMISSION_GRANTED
    }
    return true
  }

  private fun requestNotificationPermission(result: MethodChannel.Result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      result.success(true)
      return
    }
    if (hasNotificationPermission()) {
      result.success(true)
      return
    }
    // Only one dialog can be in flight; answer any earlier caller first.
    pendingPermissionResult?.success(false)
    pendingPermissionResult = result
    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIFICATIONS)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode != REQ_POST_NOTIFICATIONS) return
    val granted = grantResults.isNotEmpty() &&
        grantResults[0] == PackageManager.PERMISSION_GRANTED
    pendingPermissionResult?.success(granted)
    pendingPermissionResult = null
  }

  /** Android 12+ gates exact alarms behind a user-granted special permission. */
  private fun canScheduleExactAlarms(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
    val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
    return am.canScheduleExactAlarms()
  }

  private fun openExactAlarmSettings() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    try {
      startActivity(
        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
          .setData(Uri.parse("package:$packageName")),
      )
    } catch (_: Exception) {
      // Some OEM builds ship without the settings screen — fall back to the
      // generic app details page.
      try {
        startActivity(
          Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName")),
        )
      } catch (_: Exception) {
        // Nothing sensible left to do; the reminder still works inexactly.
      }
    }
  }

  private companion object {
    const val REQ_POST_NOTIFICATIONS = 2001
  }
}

/**
 * Centralized alarm scheduling. Exact one-shot alarms + self-rescheduling so
 * the daily reminder fires reliably (even in Doze) and survives reboots via
 * [BootReceiver].
 *
 * The daily reminder and the "test notification" deliberately use different
 * request codes AND different actions, so they map to distinct PendingIntents
 * — firing a test must never move or cancel the armed daily alarm.
 */
object ReminderScheduler {

  private const val REQ_REMINDER = 1001
  private const val REQ_TEST = 1002
  private const val KEY_ENABLED = "enabled"
  private const val KEY_HOUR = "hour"
  private const val KEY_MINUTE = "minute"

  fun schedule(context: Context, enabled: Boolean, hour: Int, minute: Int): Boolean {
    store(context).edit()
      .putBoolean(KEY_ENABLED, enabled)
      .putInt(KEY_HOUR, hour)
      .putInt(KEY_MINUTE, minute)
      .apply()

    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, REQ_REMINDER, ReminderReceiver.ACTION_REMINDER)

    if (!enabled) {
      am.cancel(pi)
      // cancel() drops the alarm but leaves the PendingIntent registered, so
      // a later FLAG_NO_CREATE lookup would still report "armed". Retire it.
      pi.cancel()
      return true
    }

    return scheduleExact(am, pi, nextTriggerMillis(hour, minute))
  }

  /**
   * True only when the user has the reminder switched on AND an alarm is
   * actually registered — the stored flag alone can outlive a cancelled
   * alarm, and the PendingIntent alone can outlive a disabled reminder.
   */
  fun hasSchedule(context: Context): Boolean {
    if (!store(context).getBoolean(KEY_ENABLED, false)) return false
    val pi = pendingIntent(
      context, REQ_REMINDER, ReminderReceiver.ACTION_REMINDER, noCreate = true,
    )
    return pi != null
  }

  /** One-shot exact-fire test on its own PendingIntent slot. */
  fun scheduleTest(context: Context, seconds: Long): Boolean {
    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    val pi = pendingIntent(context, REQ_TEST, ReminderReceiver.ACTION_TEST)
    return scheduleExact(am, pi, System.currentTimeMillis() + seconds * 1000)
  }

  fun scheduleNextDay(context: Context) {
    val sp = store(context)
    if (!sp.getBoolean(KEY_ENABLED, false)) return
    val hour = sp.getInt(KEY_HOUR, 21)
    val minute = sp.getInt(KEY_MINUTE, 0)
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
