import 'package:flutter/services.dart';

/// One tippable token, as published by the native layer.
class TipToken {
  final String symbol;
  final double min;
  final double max;
  final int decimals;

  const TipToken({
    required this.symbol,
    required this.min,
    required this.max,
    required this.decimals,
  });

  static TipToken? fromMap(Map<Object?, Object?> m) {
    final symbol = m['symbol'] as String?;
    final min = (m['min'] as num?)?.toDouble();
    final max = (m['max'] as num?)?.toDouble();
    final decimals = (m['decimals'] as num?)?.toInt();
    if (symbol == null || min == null || max == null || decimals == null) {
      return null;
    }
    return TipToken(
      symbol: symbol,
      min: min,
      max: max,
      decimals: decimals,
    );
  }

  /// Amount shown on the preset chips, smallest first.
  List<String> get presets => switch (symbol) {
        'SOL' => const ['0.01', '0.05', '0.1'],
        _ => const ['5', '10', '50'],
      };

  /// `min` without a trailing `.0` for whole numbers, for error copy.
  String get minLabel =>
      min == min.roundToDouble() ? min.toStringAsFixed(0) : '$min';
}

/// Recipient address + tippable tokens. Both come from the native layer so the
/// address the UI displays is by construction the address the transaction
/// pays — there is no second copy to drift.
class TipConfig {
  final String recipient;
  final List<TipToken> tokens;

  const TipConfig({required this.recipient, required this.tokens});

  TipToken? token(String symbol) {
    for (final t in tokens) {
      if (t.symbol == symbol) return t;
    }
    return null;
  }
}

/// Seed Vault (Mobile Wallet Adapter) tipping via the native MethodChannel.
///
/// There is no separate "connect" step: MWA performs the authorization
/// handshake inside the same transaction flow as signing.
class WalletAuthService {
  const WalletAuthService._();
  static const WalletAuthService instance = WalletAuthService._();

  static const MethodChannel _channel = MethodChannel('visor/wallet');

  /// Recipient + per-token limits. Throws [PlatformException] if the native
  /// side is unavailable, so the UI can say so instead of showing a stale
  /// hardcoded address.
  Future<TipConfig> tipConfig() async {
    final map = await _channel.invokeMapMethod<String, Object?>('tipConfig');
    final recipient = map?['recipient'] as String?;
    final raw = map?['tokens'];
    if (recipient == null || raw is! List) {
      throw PlatformException(
        code: 'BAD_CONFIG',
        message: 'Wallet configuration unavailable',
      );
    }
    final tokens = <TipToken>[];
    for (final e in raw) {
      if (e is Map<Object?, Object?>) {
        final t = TipToken.fromMap(e);
        if (t != null) tokens.add(t);
      }
    }
    if (tokens.isEmpty) {
      throw PlatformException(
        code: 'BAD_CONFIG',
        message: 'Wallet configuration unavailable',
      );
    }
    return TipConfig(recipient: recipient, tokens: tokens);
  }

  /// Send a tip/donation from the Seed Vault wallet.
  ///
  /// [token] is "SOL" or "SKR"; [amountHuman] in human units.
  /// Returns null on success, or a human-readable error string on failure.
  Future<String?> sendTip({
    required String token,
    required double amountHuman,
  }) async {
    try {
      await _channel.invokeMethod('sendTip', {
        'token': token,
        'amount': amountHuman,
      });
      return null;
    } on PlatformException catch (e) {
      final msg = e.message == null || e.message!.isEmpty
          ? (e.code == 'NO_WALLET' ? 'No compatible wallet found' : 'Tip failed')
          : e.message!;
      return msg;
    } catch (e) {
      return e.toString();
    }
  }
}
