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
import kotlinx.coroutines.withContext
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
 *  - minimum tip amount only (dust/typo guard); no upper cap — the sender's
 *    wallet balance is the ceiling and Seed Vault approves the real tx.
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

  /** Last successfully authorized wallet — cached so sendTip can pre-check
   *  the SKR balance WITHOUT opening the Seed Vault UI first. */
  @Volatile
  private var lastAuthOwner: SolanaPublicKey? = null

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
            lastAuthOwner = SolanaPublicKey(pubkey)
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
  // Mainnet SKR (Seeker) mint — verified on-chain (owner Tokenkeg, decimals=6)
  // and via real Raydium liquidity. NOTE: SKRjs1DEM... (with a literal '0') is
  // a scam entry and also invalid base58.
  private const val SKR_MINT = "SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3"
  private const val SKR_DECIMALS = 6
  // Public mainnet RPC endpoints, tried in order. The official one
  // rate-limits anonymous mobile traffic (429/403), so keep a fallback.
  private val RPCS = listOf(
    "https://api.mainnet-beta.solana.com",
    "https://solana-rpc.publicnode.com",
  )

  // Minimum tip amounts (dust/typo guard). No upper cap by design.
  private const val SOL_MIN = 0.001
  private const val SKR_MIN = 5.0

  // Lamport headroom kept on top of a SOL tip for the network fee
  // (~5000 lamports) so the balance check doesn't greenlight an unpayable tx.
  private const val SOL_FEE_BUFFER = 100_000L

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
          val min = if (token == "SOL") SOL_MIN else SKR_MIN
          result.error("BAD_AMOUNT", "Minimum tip is $min $token", null)
          return@launch
        }

        val recipient = SolanaPublicKey.from(RECIPIENT)

        // Pre-check balances BEFORE opening the wallet UI: an exception
        // thrown inside transact{} surfaces as a masked "cancelled" error.
        // Skipped silently when there is no cached auth or all RPCs are down
        // (bal == null) — the in-transact check below is the safety net.
        val cached = lastAuthOwner
        if (cached != null) {
          if (token == "SKR") {
            val ata = deriveAta(cached, SolanaPublicKey.from(SKR_MINT))
            val bal = ata?.let { tokenBalanceBase(it) }
            if (bal != null && bal < amountBase) {
              result.error(
                "TIP_FAILED",
                if (bal == 0L) "No SKR in your wallet (balance 0)"
                else "Not enough SKR: have ${bal / 1_000_000.0}, need ${amountBase / 1_000_000.0}",
                null,
              )
              return@launch
            }
          } else {
            val bal = lamportBalance(cached)
            if (bal != null && bal < amountBase + SOL_FEE_BUFFER) {
              result.error(
                "TIP_FAILED",
                if (bal == 0L) "No SOL in your wallet (balance 0)"
                else "Not enough SOL: have ${bal / 1_000_000_000.0}, need ${amountBase / 1_000_000_000.0} + fee",
                null,
              )
              return@launch
            }
          }
        }

        val txResult = walletAdapter.transact(s) { auth ->
          val ownerBytes = auth.accounts.firstOrNull()?.publicKey
            ?: throw IllegalStateException("no authorized account")
          val owner = SolanaPublicKey(ownerBytes)

          // Fetch blockhash as late as possible — it expires ~60-90 s after
          // being issued, and the user spends that time in the wallet UI.
          val blockhash = getRecentBlockhash()
            ?: throw IllegalStateException("recent blockhash unavailable")

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
            Log.w(TAG, "tip failed: ${txResult.message}", txResult.e)
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
    val min = if (token == "SOL") SOL_MIN else SKR_MIN
    if (amountHuman < min) return -1
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
    "SOL" -> {
      // Self-check: fail fast with a clear message instead of a Seed Vault
      // simulation error when the sender can't cover amount + fee.
      val bal = lamportBalance(owner)
      if (bal != null && bal < amountBase + SOL_FEE_BUFFER) {
        throw IllegalStateException(
          if (bal == 0L) "No SOL in your wallet (balance 0)"
          else "Not enough SOL: have ${bal / 1_000_000_000.0}, need ${amountBase / 1_000_000_000.0} + fee"
        )
      }
      listOf(SystemProgram.transfer(owner, recipient, amountBase))
    }
    "SKR" -> {
      val mint = SolanaPublicKey.from(SKR_MINT)
      val fromAta = deriveAta(owner, mint)
        ?: throw IllegalStateException("cannot derive owner ATA")
      val toAta = deriveAta(recipient, mint)
        ?: throw IllegalStateException("cannot derive recipient ATA")
      // Self-check: fail fast with a clear message instead of a Seed Vault
      // simulation error when the sender has no/insufficient SKR.
      val bal = tokenBalanceBase(fromAta)
      if (bal != null && bal < amountBase) {
        throw IllegalStateException(
          if (bal == 0L) "No SKR in your wallet (balance 0)"
          else "Not enough SKR: have ${bal / 1_000_000.0}, need ${amountBase / 1_000_000.0}"
        )
      }
      val instrs = mutableListOf<com.solana.transaction.TransactionInstruction>()
      // Recipient's SKR ATA must exist or the token has nowhere to land.
      // Create it in the same tx (owner pays the tiny rent) ONLY when we are
      // sure it's missing: rpcCall->null (RPC outage) used to mean false, which
      // added createATA for an existing ATA -> simulation "already in use" fail.
      // (This lib has no idempotent createIdempotent variant.)
      val ataExists = accountExists(toAta)
      if (ataExists == false) {
        instrs += AssociatedTokenProgram.createAssociatedTokenAccount(
          mint = mint,
          associatedAccount = toAta,
          owner = recipient,
          payer = owner,
        )
      } else if (ataExists == null) {
        Log.w(TAG, "recipient ATA existence unknown (RPC failed) — skipping createATA")
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
    val tokenId = TokenProgram.PROGRAM_ID
    // Canonical SPL ATA derivation: PDA under ATA program with seeds in
    // this exact order — [wallet, token_program, mint]. Any other order
    // yields a different (wrong) PDA and the tx fails simulation.
    val seeds = listOf(owner.bytes, tokenId.bytes, mint.bytes)
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
  private suspend fun getRecentBlockhash(): String? = withContext(Dispatchers.IO) {
    rpcCall(
      """
      {"jsonrpc":"2.0","id":1,
       "method":"getLatestBlockhash",
       "params":[{"commitment":"confirmed"}]}
      """.trimIndent(),
    )
      ?.let {
        val result = it.optJSONObject("result") ?: return@withContext null
        val value = result.optJSONObject("value")
        value?.optString("blockhash")
      }
  }

  /** true = exists, false = definitely absent, null = RPC unknown. */
  private suspend fun accountExists(pubkey: SolanaPublicKey): Boolean? = withContext(Dispatchers.IO) {
    val req = JSONObject().put("jsonrpc", "2.0").put("id", 1)
      .put("method", "getAccountInfo").put("params", org.json.JSONArray().put(pubkey.address))
    val resp = rpcCall(req.toString()) ?: return@withContext null
    val value = resp.optJSONObject("result")?.optJSONObject("value")
    value != null
  }

  /**
   * SKR balance of a token account in base units.
   * 0 if the account does not exist; null if all RPCs failed (caller then
   * skips the pre-check rather than blocking a healthy wallet).
   */
  private suspend fun tokenBalanceBase(ata: SolanaPublicKey): Long? = withContext(Dispatchers.IO) {
    val req = JSONObject().put("jsonrpc", "2.0").put("id", 1)
      .put("method", "getTokenAccountBalance")
      .put("params", org.json.JSONArray().put(ata.address))
    for (url in RPCS) {
      val resp = rpcPostRaw(url, req.toString()) ?: continue
      val err = resp.optJSONObject("error")
      if (err != null) {
        // -32602 "Invalid param: could not find account" => no ATA => 0 balance.
        if (err.optInt("code") == -32602) return@withContext 0L
        continue // other RPC error: try next endpoint
      }
      val amount = resp.optJSONObject("result")
        ?.optJSONObject("value")?.optString("amount") ?: continue
      return@withContext amount.toLongOrNull()
    }
    null
  }

  /**
   * Lamport balance of a wallet; null if all RPCs failed (caller then skips
   * the pre-check rather than blocking a healthy wallet).
   */
  private suspend fun lamportBalance(owner: SolanaPublicKey): Long? = withContext(Dispatchers.IO) {
    val req = JSONObject().put("jsonrpc", "2.0").put("id", 1)
      .put("method", "getBalance")
      .put("params", org.json.JSONArray().put(owner.address))
    for (url in RPCS) {
      val resp = rpcPostRaw(url, req.toString()) ?: continue
      if (resp.has("error")) continue
      val v = resp.optJSONObject("result")?.optLong("value", -1L) ?: continue
      if (v >= 0) return@withContext v
    }
    null
  }

  private fun rpcCall(body: String): JSONObject? {
    for (url in RPCS) {
      val resp = rpcPost(url, body)
      if (resp != null) return resp
    }
    return null
  }

  private fun rpcPost(url: String, body: String): JSONObject? {
    val json = rpcPostRaw(url, body) ?: return null
    if (json.has("error")) {
      Log.w(TAG, "rpc $url -> ${json.optString("error")}")
      return null
    }
    return json
  }

  /** POST without JSON-RPC "error" filtering — caller inspects errors itself. */
  private fun rpcPostRaw(url: String, body: String): JSONObject? {
    return try {
      val conn = URL(url).openConnection() as HttpURLConnection
      conn.requestMethod = "POST"
      conn.doOutput = true
      conn.connectTimeout = 15000
      conn.readTimeout = 15000
      conn.setRequestProperty("Content-Type", "application/json")
      conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
      val code = conn.responseCode
      if (code !in 200..299) {
        Log.w(TAG, "rpc $url -> HTTP $code")
        return null
      }
      val text = conn.inputStream.bufferedReader().use { it.readText() }
      JSONObject(text)
    } catch (e: Exception) {
      Log.e(TAG, "rpc $url failed", e)
      null
    }
  }
}
