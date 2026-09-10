package com.visor.app

import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.Solana
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.programs.AssociatedTokenProgram
import com.solana.programs.SystemProgram
import com.solana.programs.TokenProgram
import com.solana.publickey.SolanaPublicKey
import com.solana.transaction.Message
import com.solana.transaction.Transaction
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Seed Vault (Mobile Wallet Adapter) connect + tip/donate flow.
 *
 *  - authorize(): existing auth (public key only, no signing).
 *  - sendTip(): build a SOL or SKR transfer tx and have the user sign +
 *    broadcast it in Seed Vault via signAndSendTransactions.
 *
 * IMPORTANT: ActivityResultSender must be created (registerForActivityResult)
 * before the activity reaches STARTED/RESUMED. We attach it in
 * configureFlutterEngine (pre-STARTED) so the launcher registration is legal.
 *
 * Tip safety:
 *  - recipient is a fixed constant (the publisher's Solana address), never
 *    user-supplied.
 *  - token is whitelisted (SOL or SKR only) — no arbitrary mints.
 *  - amount clamped to sane min/max so a mistyped value can't drain the wallet.
 *  - user must approve the real transaction in the Seed Vault app.
 */
object WalletConnect {

  private const val TAG = "VisorWallet"

  private val walletAdapter = MobileWalletAdapter(
    connectionIdentity = ConnectionIdentity(
      identityUri = Uri.parse("https://visor-mobile.pages.dev/"),
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
    kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch {
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

  // ---- Tip/donate -------------------------------------------------------

  private const val RECIPIENT = "H2gnCCWcAtjgRYVPdCLv37zFdPu4TsdLwfMzvedKXW5w"
  private const val SKR_MINT = "SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3"
  private const val SKR_DECIMALS = 6
  private const val RPC = "https://api.mainnet-beta.solana.com"

  private const val MIN_HUMAN = 0.01
  private const val SOL_MAX = 1.0
  private const val SKR_MAX = 1000.0

  /**
   * Send a tip from the (pre-authorized) Seed Vault wallet.
   * [token] is "SOL" or "SKR"; [amountHuman] in human units.
   */
  fun sendTip(
    activity: ComponentActivity,
    token: String,
    amountHuman: Double,
    result: MethodChannel.Result,
  ) {
    val s = sender ?: ActivityResultSender(activity).also { sender = it }
    // Always mainnet: SKR/SOL tips live there. The adapter defaults to Devnet,
    // so set explicitly or the mint/tx won't exist on the cluster.
    walletAdapter.blockchain = Solana.Mainnet

    kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch {
      try {
        val amountBase = baseUnits(token, amountHuman)
        if (amountBase < 0) {
          result.error("BAD_AMOUNT", "amount out of range", null); return@launch
        }

        val recipient = SolanaPublicKey.from(RECIPIENT)
        val blockhash = getRecentBlockhash()
          ?: run { result.error("NO_BLOCKHASH", "recent blockhash unavailable", null); return@launch }

        val txResult = walletAdapter.transact(s) { auth ->
          val ownerBytes = auth.accounts.firstOrNull()?.publicKey
            ?: throw IllegalStateException("no authorized account")
          val owner = SolanaPublicKey(ownerBytes)

          val instructions = buildInstructions(token, recipient, owner, amountBase)

          val message = Message.Builder().apply {
            instructions.forEach { addInstruction(it) }
            setRecentBlockhash(blockhash)
          }.build()
          signAndSendTransactions(Transaction(message))
        }

        when (txResult) {
          is TransactionResult.Success -> {
            result.success(mapOf("ok" to true))
          }
          is TransactionResult.NoWalletFound -> {
            result.error("NO_WALLET", txResult.message, null)
          }
          is TransactionResult.Failure -> {
            result.error("TIP_FAILED", "${txResult.message}: ${txResult.e.message}", null)
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "sendTip failed", e)
        result.error("TIP_EXCEPTION", e.message ?: e.toString(), null)
      }
    }
  }

  private fun baseUnits(token: String, amountHuman: Double): Long {
    val max = if (token == "SOL") SOL_MAX else SKR_MAX
    if (amountHuman < MIN_HUMAN || amountHuman > max) return -1
    return when (token) {
      "SOL" -> (amountHuman * 1_000_000_000).toLong()
      "SKR" -> (amountHuman * 1_000_000).toLong()
      else -> -1
    }
  }

  private suspend fun buildInstructions(
    token: String,
    recipient: SolanaPublicKey,
    owner: SolanaPublicKey,
    amountBase: Long,
  ): List<com.solana.transaction.TransactionInstruction> = when (token) {
    "SOL" -> listOf(SystemProgram.transfer(owner, recipient, amountBase))
    "SKR" -> {
      val mint = SolanaPublicKey.from(SKR_MINT)
      val fromAta = deriveAta(owner, mint)
        ?: throw IllegalStateException("cannot derive owner ATA")
      val toAta = deriveAta(recipient, mint)
        ?: throw IllegalStateException("cannot derive recipient ATA")
      val instrs = mutableListOf<com.solana.transaction.TransactionInstruction>()
      // Recipient's SKR ATA must exist or the token has nowhere to land.
      // Create it in the same tx (owner pays the tiny rent) if missing.
      if (!accountExists(toAta)) {
        instrs += AssociatedTokenProgram.createAssociatedTokenAccount(
          mint = mint,
          associatedAccount = toAta,
          owner = recipient,
          payer = owner,
        )
      }
      instrs += TokenProgram.transferChecked(
        from = fromAta,
        to = toAta,
        amount = amountBase,
        decimals = SKR_DECIMALS.toByte(),
        owner = owner,
        mint = mint,
      )
      instrs
    }
    else -> throw IllegalArgumentException("unknown token: $token")
  }

  private suspend fun deriveAta(owner: SolanaPublicKey, mint: SolanaPublicKey): SolanaPublicKey? {
    val ataId = AssociatedTokenProgram.PROGRAM_ID
    val tokenId = TokenProgram.PROGRAM_ID
    val seeds = listOf(ataId.bytes, owner.bytes, tokenId.bytes, mint.bytes)
    return try {
      val pda = AssociatedTokenProgram.findDerivedAddress(seeds).getOrThrow()
      SolanaPublicKey(pda.bytes)
    } catch (e: Exception) {
      Log.e(TAG, "deriveAta failed", e)
      null
    }
  }

  /** getRecentBlockhash via mainnet JSON-RPC (MWA has no RPC wrapper).
   *  Note: getRecentBlockhash is removed from the public RPC; use
   *  getLatestBlockhash with the modern object params. */
  private fun getRecentBlockhash(): String? =
    rpcCall(
      """
      {"jsonrpc":"2.0","id":1,
       "method":"getLatestBlockhash",
       "params":[{"commitment":"confirmed"}]}
      """.trimIndent(),
    )
      ?.let {
        val result = it.optJSONObject("result") ?: return null
        val value = result.optJSONObject("value")
        value?.optString("blockhash")
      }

  private fun accountExists(pubkey: SolanaPublicKey): Boolean {
    val params = JSONObject().put("encoding", "base64").put("commitment", "confirmed")
    val req = JSONObject().put("jsonrpc", "2.0").put("id", 1)
      .put("method", "getAccountInfo").put("params", org.json.JSONArray().put(pubkey.address))
    val resp = rpcCall(req.toString()) ?: return false
    val value = resp.optJSONObject("result")?.optJSONObject("value")
    return value != null
  }

  private fun rpcCall(body: String): JSONObject? {
    return try {
      val conn = URL(RPC).openConnection() as HttpURLConnection
      conn.requestMethod = "POST"
      conn.doOutput = true
      conn.setRequestProperty("Content-Type", "application/json")
      conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
      val code = conn.responseCode
      val stream = if (code in 200..299) conn.inputStream else conn.errorStream
      val text = stream.bufferedReader().use { it.readText() }
      JSONObject(text)
    } catch (e: Exception) {
      Log.e(TAG, "rpc failed", e)
      null
    }
  }
}