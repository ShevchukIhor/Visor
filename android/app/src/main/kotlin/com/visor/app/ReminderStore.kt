package com.visor.app

import android.content.Context
import android.content.SharedPreferences
import java.util.Calendar

/**
 * Persists the "last trained" marker and the active reminder countdown state
 * in SharedPreferences. The Dart layer writes `mark_trained` after saving a
 * session; the receiver reads it at fire time to decide whether to notify.
 */
object ReminderStore {

  private const val PREFS = "visor_reminder"
  private const val KEY_LAST_TRAINED = "last_trained_ms"

  private fun prefs(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /** Record that a session completed at [ts]. */
  fun markTrained(context: Context, ts: Long) {
    prefs(context).edit().putLong(KEY_LAST_TRAINED, ts).apply()
  }

  /** True if a session completed at any point today (local calendar day). */
  fun trainedToday(context: Context): Boolean {
    val last = prefs(context).getLong(KEY_LAST_TRAINED, 0L)
    if (last == 0L) return false
    val now = Calendar.getInstance()
    val c = Calendar.getInstance().apply { timeInMillis = last }
    return c.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
        c.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR)
  }
}