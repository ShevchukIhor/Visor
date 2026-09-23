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
import com.solana.transaction.TransactionInstruction
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.net.HttpURLConnection
import java.net.URL

/**
 * Seed Vault (Mobile Wallet Adapter) tip/donate flow.
 *
 * sendTip() builds a SOL or SKR transfer tx and has the user authorize, sign
 * and broadcast it in Seed Vault via signAndSendTransactions — MWA handles
 * the authorization handshake inside transact{}, so no separate connect step
 * is needed.
 *
 * IMPORTANT: ActivityResultSender must be created (registerForActivityResult)
 * before the activity reaches STARTED/RESUMED. We create it in [attach], which
 * MainActivity calls from configureFlutterEngine (pre-STARTED), and drop it in
 * [detach] so it never outlives the Activity it was registered against.
 *
 * Tip safety:
 *  - recipient is a fixed constant (the publisher's Solana address), never
 *    user-supplied. [tipConfig] publishes it to the UI so the displayed
 *    address and the transacted address cannot drift apart.
 *  - token is whitelisted (SOL or SKR only) — no arbitrary mints.
 *  - amount is bounded at both ends (dust/typo guard below, sanity cap above)
 *    and converted through BigDecimal so no rounding cent goes missing.
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
  ).apply {
    // Always mainnet: SKR/SOL tips live there. The adapter defaults to Devnet,
    // so it is set once here — authorization and signing must not disagree
    // about the cluster.
    blockchain = Solana.Mainnet
  }

  /** Activity-scoped; both are replaced on attach and cleared on detach. */
  private var sender: ActivityResultSender? = null
  private var host: ComponentActivity? = null
  private var scope: CoroutineScope? = null

  /** Last authorized wallet — lets a repeat tip pre-check the balance
   *  WITHOUT opening the Seed Vault UI first. */
  @Volatile
  private var lastAuthOwner: SolanaPublicKey? = null

  /**
   * Called from configureFlutterEngine — before the activity is STARTED.
   * Always rebuilds the sender: a cached one from a previous Activity
   * instance holds a dead launcher (and leaks that Activity).
   */
  fun attach(activity: ComponentActivity) {
    if (host === activity && sender != null) return
    scope?.cancel()
    sender = ActivityResultSender(activity)
    host = activity
    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
  }

  /** Called from onDestroy — releases the Activity and cancels in-flight work. */
  fun detach(activity: ComponentActivity) {
    if (host !== activity) return
    scope?.cancel()
    scope = null
    sender = null
    host = null
  }

  // ---- Tip/donate -------------------------------------------------------

  private const val RECIPIENT = "H2gnCCWcAtjgRYVPdCLv37zFdPu4TsdLwfMzvedKXW5w"
  // Mainnet SKR (Seeker) mint — verified on-chain (owner Tokenkeg, decimals=6)
  // and via real Raydium liquidity. NOTE: SKRjs1DEM... (with a literal '0') is
  // a scam entry and also invalid base58.
  private const val SKR_MINT = "SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3"
  private const val SKR_DECIMALS = 6
  private const val SOL_DECIMALS = 9
  // Public mainnet RPC endpoints, tried in order. The official one
  // rate-limits anonymous mobile traffic (429/403), so keep a fallback.
  private val RPCS = listOf(
    "https://api.mainnet-beta.solana.com",
    "https://solana-rpc.publicnode.com",
  )

  // Minimum tip amounts (dust/typo guard).
  private const val SOL_MIN = 0.001
  private const val SKR_MIN = 5.0
  // Upper sanity caps. Not a policy on generosity — a guard against a
  // mistyped "1e9" silently overflowing the base-unit conversion.
  private const val SOL_MAX = 1_000.0
  private const val SKR_MAX = 10_000_000.0

  // Lamport headroom kept on top of a SOL tip for the network fee
  // (~5000 lamports) so the balance check doesn't greenlight an unpayable tx.
  private const val SOL_FEE_BUFFER = 100_000L

  /** Recipient + per-token limits, so the Dart UI keeps no second copy. */
  fun tipConfig(): Map<String, Any?> = mapOf(
    "recipient" to RECIPIENT,
    "tokens" to listOf(
      mapOf("symbol" to "SOL", "min" to SOL_MIN, "max" to SOL_MAX, "decimals" to SOL_DECIMALS),
      mapOf("symbol" to "SKR", "min" to SKR_MIN, "max" to SKR_MAX, "decimals" to SKR_DECIMALS),
    ),
  )

  /**
   * Send a tip from the Seed Vault wallet.
   * [token] is "SOL" or "SKR"; [amountHuman] in human units.
   */
  fun sendTip(
    activity: ComponentActivity,
    token: String,
    amountHuman: Double,
    result: MethodChannel.Result,
  ) {
    attach(activity)
    val s = sender
    val launchScope = scope
    if (s == null || launchScope == null) {
      result.error("TIP_EXCEPTION", "Wallet bridge is not attached", null)
      return
    }

    launchScope.launch {
      // A failure raised inside transact{} comes back as a masked, generic
      // error, so the real reason is stashed here and preferred on failure.
      var preflightError: String? = null
      try {
        val amount = baseUnits(token, amountHuman)
        if (amount is AmountResult.Invalid) {
          result.error("BAD_AMOUNT", amount.message, null)
          return@launch
        }
        val amountBase = (amount as AmountResult.Ok).base

        val recipient = SolanaPublicKey.from(RECIPIENT)

        // Pre-check balances BEFORE opening the wallet UI when a previous tip
        // already told us who the owner is. Skipped silently when there is no
        // cached owner or all RPCs are down (bal == null) — the in-transact
        // check below is the safety net.
        lastAuthOwner?.let { cached ->
          insufficientFunds(token, cached, amountBase)?.let { msg ->
            result.error("TIP_FAILED", msg, null)
            return@launch
          }
        }

        val txResult = walletAdapter.transact(s) { auth ->
          val ownerBytes = auth.accounts.firstOrNull()?.publicKey
            ?: throw IllegalStateException("no authorized account")
          val owner = SolanaPublicKey(ownerBytes)
          lastAuthOwner = owner

          insufficientFunds(token, owner, amountBase)?.let { msg ->
            preflightError = msg
            throw IllegalStateException(msg)
          }

          // Fetch blockhash as late as possible — it expires ~60-90 s after
          // being issued, and the user spends that time in the wallet UI.
          val blockhash = getRecentBlockhash()
            ?: run {
              preflightError = "Solana network unreachable — try again"
              throw IllegalStateException("recent blockhash unavailable")
            }

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
            val reason = preflightError
              ?: "${txResult.message}: ${txResult.e.message}"
            result.error("TIP_FAILED", reason, null)
          }
        }
      } catch (e: CancellationException) {
        throw e
      } catch (e: Exception) {
        Log.e(TAG, "sendTip failed", e)
        result.error(
          "TIP_EXCEPTION",
          preflightError ?: e.message ?: e.toString(),
          null,
        )
      }
    }
  }

  private sealed interface AmountResult {
    data class Ok(val base: Long) : AmountResult
    data class Invalid(val message: String) : AmountResult
  }

  /**
   * Human units -> base units. BigDecimal rather than a raw Double multiply:
   * `(0.29 * 1_000_000_000).toLong()` truncates to 289_999_999.
   */
  private fun baseUnits(token: String, amountHuman: Double): AmountResult {
    val limits = when (token) {
      "SOL" -> Triple(SOL_MIN, SOL_MAX, SOL_DECIMALS)
      "SKR" -> Triple(SKR_MIN, SKR_MAX, SKR_DECIMALS)
      else -> return AmountResult.Invalid("Unsupported token: $token")
    }
    val (min, max, decimals) = limits
    if (!amountHuman.isFinite()) {
      return AmountResult.Invalid("Enter a valid amount")
    }
    if (amountHuman < min) {
      return AmountResult.Invalid("Minimum tip is $min $token")
    }
    if (amountHuman > max) {
      return AmountResult.Invalid("Maximum tip is $max $token")
    }
    val base = BigDecimal.valueOf(amountHuman)
      .setScale(decimals, RoundingMode.HALF_UP)
      .movePointRight(decimals)
      .toBigIntegerExact()
    if (base.bitLength() >= 63) {
      return AmountResult.Invalid("Maximum tip is $max $token")
    }
    return AmountResult.Ok(base.toLong())
  }

  /**
   * Null when the owner can afford the tip (or the balance is unknown because
   * every RPC failed); otherwise a message explaining the shortfall.
   */
  private suspend fun insufficientFunds(
    token: String,
    owner: SolanaPublicKey,
    amountBase: Long,
  ): String? = when (token) {
    "SKR" -> {
      val ata = deriveAta(owner, SolanaPublicKey.from(SKR_MINT))
      val bal = ata?.let { tokenBalanceBase(it) }
      if (bal != null && bal < amountBase) {
        if (bal == 0L) "No SKR in your wallet (balance 0)"
        else "Not enough SKR: have ${bal.toDouble() / 1_000_000.0}, " +
            "need ${amountBase.toDouble() / 1_000_000.0}"
      } else {
        null
      }
    }
    else -> {
      val bal = lamportBalance(owner)
      if (bal != null && bal < amountBase + SOL_FEE_BUFFER) {
        if (bal == 0L) "No SOL in your wallet (balance 0)"
        else "Not enough SOL: have ${bal.toDouble() / 1_000_000_000.0}, " +
            "need ${amountBase.toDouble() / 1_000_000_000.0} + fee"
      } else {
        null
      }
    }
  }

  private suspend fun buildInstructions(
    token: String,
    recipient: SolanaPublicKey,
    owner: SolanaPublicKey,
    amountBase: Long,
  ): List<TransactionInstruction> = when (token) {
    "SOL" -> listOf(SystemProgram.transfer(owner, recipient, amountBase))
    "SKR" -> {
      val mint = SolanaPublicKey.from(SKR_MINT)
      val fromAta = deriveAta(owner, mint)
        ?: throw IllegalStateException("cannot derive owner ATA")
      val toAta = deriveAta(recipient, mint)
        ?: throw IllegalStateException("cannot derive recipient ATA")
      val instrs = mutableListOf<TransactionInstruction>()
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
    var conn: HttpURLConnection? = null
    return try {
      conn = (URL(url).openConnection() as HttpURLConnection).apply {
        requestMethod = "POST"
        doOutput = true
        connectTimeout = 15000
        readTimeout = 15000
        setRequestProperty("Content-Type", "application/json")
      }
      conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
      val code = conn.responseCode
      if (code !in 200..299) {
        // Drain errorStream: the body carries the RPC's reason (rate limit,
        // bad request), and an undrained stream is not returned to the pool.
        val detail = conn.errorStream?.bufferedReader()?.use { it.readText() }
          ?.take(200).orEmpty()
        Log.w(TAG, "rpc $url -> HTTP $code $detail")
        return null
      }
      val text = conn.inputStream.bufferedReader().use { it.readText() }
      JSONObject(text)
    } catch (e: Exception) {
      Log.e(TAG, "rpc $url failed", e)
      null
    } finally {
      conn?.disconnect()
    }
  }
}
