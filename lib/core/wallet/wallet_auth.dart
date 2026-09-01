import 'package:flutter/services.dart';

import 'base58.dart';

/// Result of a wallet address resolution.
class WalletAuth {
  final String address; // base58 public key
  final String? accountLabel;

  const WalletAuth({required this.address, required this.accountLabel});
}

/// Seed Vault (Mobile Wallet Adapter) authorization via the native
/// MethodChannel. Returns the base58 public key + optional label.
class WalletAuthService {
  const WalletAuthService._();
  static const WalletAuthService instance = WalletAuthService._();

  static const MethodChannel _channel = MethodChannel('visor/wallet');

  /// Authorize via Seed Vault. Returns null if cancelled/unavailable.
  /// On failure, rethrows the underlying PlatformException so the UI can
  /// surface the real error instead of a generic "unavailable".
  Future<WalletAuth?> authorize() async {
    final map = await _channel.invokeMapMethod('authorizeWallet');
    if (map == null) return null;
    final bytes = map['pubkey_bytes'];
    final label = map['label'] as String?;
    if (bytes is! List) return null;
    final uint8 = Uint8List.fromList(
      bytes.map((e) => (e as num).toInt() & 0xFF).toList(),
    );
    if (uint8.length < 32) return null;
    return WalletAuth(address: base58Encode(uint8), accountLabel: label);
  }

  /// True if this wallet address looks like a base58 pubkey (32..44 chars).
  static bool isValidAddress(String addr) {
    final s = addr.trim();
    if (s.isEmpty) return false;
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    for (final c in s.runes) {
      final ch = String.fromCharCode(c);
      if (!alphabet.contains(ch)) return false;
    }
    return s.length >= 32 && s.length <= 44;
  }
}