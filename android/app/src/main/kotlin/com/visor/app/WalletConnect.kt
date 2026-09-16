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
 * CORRECT MWA PATTERN (per Solana Mobile docs):
 * Both authorize() and sendTip() use transact() with auth callback.
 * MWA handles session/authToken internally - don't manually set walletAdapter.authToken.
 */
object WalletConnect {

  private const val TAG = "VisorWallet"

  private val walletAdapter = MobileWalletAdapter(
    connectionIdentity = ConnectionIdentity(
      identityUri = Uri.parse("https://visor-mobile.pages.dev/"),
      iconUri = Uri.parse("icon.png"),
      identityName = "Visor \u2014 Vision Training",
    ),
  )

  @Volatile
  private var sender: ActivityResultSender? = null

  fun attach(activity: ComponentActivity) {
    if (sender == null) {
      sender = ActivityResultSender(activity)
    }
  }

  private fun getSender(activity: ComponentActivity): ActivityResultSender {
    return sender ?: ActivityResultSender(activity).also { sender = it }
  }

  /** Authorize wallet - transact() with auth callback */
  fun authorize(activity: ComponentActivity, result: MethodChannel.Result) {
    val s = getSender(activity)
    
    kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch {
      try {
        val txResult = walletAdapter.transact(s) { authResult ->
          Log.w(TAG, "authResult.accounts count: ${authResult.accounts.size}")
          for ((i, acct) in authResult.accounts.withIndex()) {
            Log.w(TAG, "  account[$i]: label='${acct.accountLabel}' pubkey=${acct.publicKey?.joinToString(",")}")
          }
          authResult.accounts.firstOrNull()?.publicKey
        }
        
        when (txResult) {
          is TransactionResult.Success -> {
            val userPubkey = txResult.authResult.accounts.firstOrNull()?.publicKey
              ?: throw IllegalStateException("no account in authResult")
            val owner = SolanaPublicKey(userPubkey)
            
            Log.w(TAG, "Authorized owner: ${owner.address}")
            
            val map = mutableMapOf<String, Any?>()
            map["pubkey_bytes"] = owner.bytes.map { it.toInt() and 0xFF }
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
  private val RPCS = listOf(
    "https://api.mainnet-beta.solana.com",
    "https://solana-rpc.publicnode.com",
  )

  private const val SOL_MAX = 1.0
  private const val SKR_MAX = 1000.0

  /** Send tip - transact() with auth callback (MWA handles session) */
  fun sendTip(
    activity: ComponentActivity,
    token: String,
    amountHuman: Double,
    result: MethodChannel.Result,
  ) {
    Log.w(TAG, ">>> sendTip ENTRY token=$token amount=$amountHuman")
    val s = getSender(activity)
    walletAdapter.blockchain = Solana.Mainnet

    kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch {
      try {
        val amountBase = baseUnits(token, amountHuman)
        Log.w(TAG, "amountBase: $amountBase for token: $token")
        if (amountBase < 0) {
          result.error("BAD_AMOUNT", "amount out of range", null); return@launch
        }

        val recipient = SolanaPublicKey.from(RECIPIENT)
        Log.w(TAG, "Fetching recent blockhash...")
        val blockhash = getRecentBlockhash()
          ?: run { 
            Log.e(TAG, "Failed to get blockhash")
            result.error("NO_BLOCKHASH", "recent blockhash unavailable", null); return@launch 
          }
        Log.w(TAG, "Got blockhash: $blockhash")

        Log.w(TAG, "Starting transact for tip...")
        // transact() WITH auth callback - MWA handles session internally
        val txResult = walletAdapter.transact(s) { auth ->
          Log.w(TAG, "transact auth callback: accounts=${auth.accounts.size}")
          for ((i, acct) in auth.accounts.withIndex()) {
            Log.w(TAG, "  account[$i]: label='${acct.accountLabel}' pubkey=${acct.publicKey?.joinToString(",")}")
          }
          
          // Build and send transaction
          val userPubkey = auth.accounts.firstOrNull()?.publicKey
            ?: throw IllegalStateException("no authorized account")
          val ownerToUse = SolanaPublicKey(userPubkey)  // WRAP ByteArray in SolanaPublicKey
          Log.w(TAG, "Using owner: ${ownerToUse.address}")
          val instructions = buildInstructions(token, recipient, ownerToUse, amountBase)
          Log.w(TAG, "Built ${instructions.size} instructions for token: $token")

          val message = Message.Builder().apply {
            instructions.forEach { addInstruction(it) }
            setRecentBlockhash(blockhash)
          }.build()
          signAndSendTransactions(arrayOf(Transaction(message).serialize()))
        }

        when (txResult) {
          is TransactionResult.Success -> {
            Log.w(TAG, "Transaction success")
            result.success(mapOf("ok" to true))
          }
          is TransactionResult.NoWalletFound -> {
            Log.w(TAG, "no wallet: ${txResult.message}")
            result.error("NO_WALLET", txResult.message, null)
          }
          is TransactionResult.Failure -> {
            Log.w(TAG, "failure: ${txResult.message}", txResult.e)
            val msg = if (txResult.message?.contains("cancelled") == true) {
              "Wallet session expired. Please re-connect wallet and try again."
            } else {
              "${txResult.message}: ${txResult.e.message}"
            }
            result.error("TIP_FAILED", msg, null)
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "sendTip failed", e)
        result.error("TIP_EXCEPTION", e.message ?: e.toString(), null)
      }
    }
    Log.w(TAG, "<<< sendTip EXIT (launched)")
  }

  private fun baseUnits(token: String, amountHuman: Double): Long {
    val max = if (token == "SOL") SOL_MAX else SKR_MAX
    if (amountHuman <= 0 || amountHuman > max) return -1
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
      Log.w(TAG, "buildInstructions: SOL branch")
      listOf(SystemProgram.transfer(owner, recipient, amountBase))
    }
    "SKR" -> {
      Log.w(TAG, "buildInstructions: SKR branch")
      val mint = SolanaPublicKey.from(SKR_MINT)
      Log.w(TAG, "SKR mint: $mint")
      val fromAta = deriveAta(owner, mint)
        ?: throw IllegalStateException("cannot derive owner ATA")
      Log.w(TAG, "fromAta: ${fromAta.address}")
      val toAta = deriveAta(recipient, mint)
        ?: throw IllegalStateException("cannot derive recipient ATA")
      Log.w(TAG, "toAta: ${toAta.address}")
      val instrs = mutableListOf<com.solana.transaction.TransactionInstruction>()
      val toAtaExists = accountExists(toAta)
      Log.w(TAG, "toAtaExists: $toAtaExists")
      if (!toAtaExists) {
        instrs += AssociatedTokenProgram.createAssociatedTokenAccount(
          mint = mint,
          associatedAccount = toAta,
          owner = recipient,
          payer = owner,
        )
        Log.w(TAG, "Added create ATA instruction")
      }
      instrs += TokenProgram.transferChecked(
        from = fromAta,
        to = toAta,
        amount = amountBase,
        decimals = SKR_DECIMALS.toByte(),
        owner = owner,
        mint = mint,
      )
      Log.w(TAG, "Added transferChecked instruction")
      instrs
    }
    else -> {
      Log.e(TAG, "buildInstructions: UNKNOWN token=$token")
      throw IllegalArgumentException("unknown token: $token")
    }
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

  private suspend fun getRecentBlockhash(): String? = withContext(Dispatchers.IO) {
    rpcCall(
      """{"jsonrpc":"2.0","id":1,"method":"getLatestBlockhash","params":[{"commitment":"confirmed"}]}""",
    )?.let {
      val result = it.optJSONObject("result") ?: return@withContext null
      val value = result.optJSONObject("value")
      value?.optString("blockhash")
    }
  }

  private suspend fun accountExists(pubkey: SolanaPublicKey): Boolean = withContext(Dispatchers.IO) {
    val req = JSONObject().put("jsonrpc", "2.0").put("id", 1)
      .put("method", "getAccountInfo")
      .put("params", org.json.JSONArray().put(pubkey.address)
        .put(JSONObject().put("encoding", "base64").put("commitment", "confirmed")))
    val resp = rpcCall(req.toString()) ?: return@withContext false
    val value = resp.optJSONObject("result")?.optJSONObject("value")
    value != null
  }

  private suspend fun rpcCall(body: String): JSONObject? = withContext(Dispatchers.IO) {
    for (url in RPCS) {
      val resp = rpcPost(url, body)
      if (resp != null) return@withContext resp
    }
    null
  }

  private fun rpcPost(url: String, body: String): JSONObject? {
    return try {
      val conn = URL(url).openConnection() as HttpURLConnection
      conn.requestMethod = "POST"
      conn.doOutput = true
      conn.connectTimeout = 15000
      conn.readTimeout = 15000
      conn.setRequestProperty("Content-Type", "application/json")
      conn.outputStream.use { it.write(body.toByteArray(java.nio.charset.StandardCharsets.UTF_8)) }
      val code = conn.responseCode
      if (code !in 200..299) {
        Log.w(TAG, "rpc $url -> HTTP $code")
        return null
      }
      val text = conn.inputStream.bufferedReader().use { it.readText() }
      val json = JSONObject(text)
      if (json.has("error")) {
        Log.w(TAG, "rpc $url -> ${json.optString("error")}")
        return null
      }
      json
    } catch (e: Exception) {
      Log.e(TAG, "rpc $url failed", e)
      null
    }
  }
}