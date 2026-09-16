import "../wallet/mwa_platform.dart";
import "package:solana/solana.dart";
import "package:solana/src/encoder/instruction.dart";
import "package:solana/src/encoder/message/message.dart";
import "dart:typed_data";

/// Result of a wallet address resolution.
class WalletAuth {
  final String address; // base58 public key
  final String? accountLabel;

  const WalletAuth({required this.address, required this.accountLabel});
}

/// Seed Vault (Mobile Wallet Adapter) authorization via platform channel.
/// Session pattern: create -> start -> authorize/sign -> close.
class WalletAuthService {
  WalletAuthService._();
  static final WalletAuthService instance = WalletAuthService._();

  final MwaPlatform _mwa = MwaPlatform();

  /// Authorize via Seed Vault. Returns null if cancelled/unavailable.
  Future<WalletAuth?> authorize() async {
    try {
      final address = await _mwa.authorize(
        identityUri: "https://visor-mobile.pages.dev/",
        iconUri: "https://visor-mobile.pages.dev/icon.png",
        identityName: "Visor -- Vision Training",
        cluster: null, // Use default cluster
      );

      if (address == null) {
        return null;
      }

      return WalletAuth(
        address: address,
        accountLabel: "",
      );
    } catch (e) {
      print("Seed Vault authorization error: $e");
      return null;
    }
  }

  /// True if this wallet address looks like a base58 pubkey (32..44 chars).
  static bool isValidAddress(String addr) {
    final s = addr.trim();
    if (s.isEmpty) return false;
    const alphabet =
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    for (final c in s.runes) {
      final ch = String.fromCharCode(c);
      if (!alphabet.contains(ch)) return false;
    }
    return s.length >= 32 && s.length <= 44;
  }

  /// Send a tip/donation from the (pre-authorized) Seed Vault wallet.
  ///
  /// [token] is "SOL" or "SKR"; [amountHuman] in human units.
  /// Returns null on success, or a human-readable error string on failure.
  Future<String?> sendTip({required String token, required double amountHuman}) async {
    try {
      final result = await _mwa.sendTip(token: token, amountHuman: amountHuman);
      return result;
    } catch (e) {
      print("Seed Vault transaction error: $e");
      return e.toString();
    }
  }
}

class WalletConnect {
  // Solana base units: SOL has 9 decimals, SKR has no decimals defined yet - assume none
  static const int SOL_UNIT = 1000000000;
  static const int SKR_UNIT = 1;

  /// Convert human-readable amount to base units.
  List<int> baseUnits(String token, double humanAmount) {
    if (token == "SOL") {
      return [(humanAmount * SOL_UNIT).round()];
    } else {
      final skrAmount = (humanAmount * 1000000000).round();
      return [skrAmount, skrAmount];
    }
  }

  /// Build instructions for a transaction: system transfer or SPL token transfer.
  List<Instruction> buildInstructions(String token, String sender, double amount) {
    final senderKey = Ed25519HDPublicKey.fromBase58(sender);
    if (token == "SOL") {
      // Simple SOL transfer
      return [SystemInstruction.transfer(
        fundingAccount: senderKey,
        recipientAccount: Ed25519HDPublicKey.fromBase58("EgXk9mGm7yXQhP8bXcDnQdMhUzRwSjKpLvTbN5oFqWYr"),
        lamports: amount.round())];
    } else {
      // SPL token transfer with proper mint address
      final splAddress = Ed25519HDPublicKey.fromBase58("sKrtAsM3YjhtVtTqBTVFVZr1vFGrfH6Z2tXaJbNnAe");
      return [TokenInstruction.transferChecked(
        source: senderKey,
        mint: splAddress,
        destination: Ed25519HDPublicKey.fromBase58("EgXk9mGm7yXQhP8bXcDnQdMhUzRwSjKpLvTbN5oFqWYr"),
        owner: senderKey,
        amount: amount.round(),
        decimals: 9)];
    }
  }
}

class SeedVaultTransaction {
  final String pubkey;
  final List<Uint8List> instructions;

  const SeedVaultTransaction({required this.pubkey, required this.instructions});
}
