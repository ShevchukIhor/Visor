package com.visor.app

import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Seed Vault (Mobile Wallet Adapter) connect via the official Kotlin clientlib.
 *
 * IMPORTANT: ActivityResultSender must be created (registerForActivityResult)
 * before the activity reaches STARTED/RESUMED. We attach it in
 * configureFlutterEngine (pre-STARTED) so the launcher registration is legal.
 */
object WalletConnect {

  private const val TAG = "VisorWallet"

  private val walletAdapter = MobileWalletAdapter(
    connectionIdentity = ConnectionIdentity(
      identityUri = Uri.parse("https://visor.app"),
      iconUri = Uri.parse("icon.png"),
      identityName = "Visor — Vision Training",
    ),
  )

  @Volatile
  private var sender: ActivityResultSender? = null

  /** Called from configureFlutterEngine — before the activity is STARTED. */
  fun attach(activity: ComponentActivity) {
    if (sender == null) {
      sender = ActivityResultSender(activity)
    }
  }

  fun authorize(activity: ComponentActivity, result: MethodChannel.Result) {
    val s = sender ?: ActivityResultSender(activity).also { sender = it }
    CoroutineScope(Dispatchers.Main).launch {
      try {
        val txResult = walletAdapter.transact(s) { authResult ->
          authResult.accounts.firstOrNull()?.publicKey
        }
        when (txResult) {
          is TransactionResult.Success -> {
            val pubkey: ByteArray? = txResult.payload
            if (pubkey == null) {
              Log.w(TAG, "auth success but null account")
              result.success(null)
              return@launch
            }
            val map = mutableMapOf<String, Any?>()
            map["pubkey_bytes"] = pubkey.map { it.toInt() and 0xFF }
            map["auth_token"] = txResult.authResult.authToken
            val acct = txResult.authResult.accounts.firstOrNull()
            map["label"] = acct?.accountLabel
            result.success(map)
          }
          is TransactionResult.NoWalletFound -> {
            Log.w(TAG, "no wallet: ${txResult.message}")
            result.error("NO_WALLET", txResult.message, null)
          }
          is TransactionResult.Failure -> {
            Log.w(TAG, "failure: ${txResult.message}", txResult.e)
            result.error("AUTH_FAILED", "${txResult.message}: ${txResult.e.message}", null)
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "exception", e)
        result.error("AUTH_EXCEPTION", e.message ?: e.toString(), null)
      }
    }
  }
}