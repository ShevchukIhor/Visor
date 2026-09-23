import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/visor_theme.dart';
import '../core/wallet/wallet_auth.dart';

/// About / Support screen: what Visor does, how it works, privacy, a
/// medical disclaimer, and the publisher Solana address (copyable).
/// Tip/donate: a button under the address opens a sheet with token choice,
/// preset amounts, a custom field, and a thank-you screen. The address, the
/// tokens and their limits all come from the native wallet layer.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  /// Recipient + limits come from the native wallet layer, which is also what
  /// builds the transaction — so what is shown here is what actually gets
  /// paid. No second copy of the address lives in Dart.
  TipConfig? _config;
  bool _configFailed = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final c = await WalletAuthService.instance.tipConfig();
      if (!mounted) return;
      setState(() => _config = c);
    } catch (_) {
      if (!mounted) return;
      setState(() => _configFailed = true);
    }
  }

  Future<void> _copy() async {
    final address = _config?.recipient;
    if (address == null) return;
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _openTip() {
    final config = _config;
    if (config == null) return;
    showTipSheet(context, config);
  }

  /// A body paragraph with a proper first-line indent and comfortable
  /// leading (Flutter has no built-in first-line indent, so a leading
  /// [WidgetSpan] shim does the job).
  Widget _para(String text, {Color color = VisorTheme.text, double size = 14}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: color, fontSize: size, height: 1.5),
          children: [
            const WidgetSpan(child: SizedBox(width: 18)),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text("Support Visor"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _para(
                "Visor trains your visual cortex with Gabor-patch games and "
                "guided eye exercises — the same stimuli neuroscience uses "
                "to study vision. Regular short sessions can ease screen "
                "fatigue, sharpen focus, and loosen eye strain from long "
                "near-work.",
                size: 15,
              ),
              _para(
                "Each card differs by a single controlled parameter — "
                "orientation, frequency, or phase — so your brain learns to "
                "tell real visual detail apart, not just guess at noise.",
              ),
              _para(
                "Private by design: no accounts, no ads, no trackers, no "
                "telemetry. Every session is stored locally on your device "
                "and never leaves it.",
              ),
              _para(
                "Visor is a training tool, not a medical device. It does not "
                "diagnose or treat any eye condition. If you experience "
                "persistent pain, double vision, or sudden vision changes, "
                "see an eye-care professional.",
                color: VisorTheme.danger,
              ),
              const Text(
                "If Visor helped your eyes, a tip is appreciated — never "
                "required.",
                style: TextStyle(color: VisorTheme.textDim, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VisorTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Solana address",
                      style: TextStyle(
                        color: VisorTheme.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet,
                            color: VisorTheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _config?.recipient ??
                                (_configFailed
                                    ? "Wallet unavailable on this device"
                                    : "Loading\u2026"),
                            style: TextStyle(
                              color: _config == null
                                  ? VisorTheme.textDim
                                  : VisorTheme.text,
                              fontFamily: "monospace",
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _config == null ? null : _openTip,
                            icon: const Icon(Icons.volunteer_activism, size: 18),
                            label: const Text("Send a tip"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _config == null ? null : _copy,
                          child: Text(
                            _copied ? "Copied" : "Copy address",
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Opens your Seed Vault wallet — the amount and token are "
                      "yours to set. Nothing leaves your wallet unless you "
                      "confirm.",
                      style: TextStyle(
                        color: VisorTheme.textDim,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: pick a token (SKR default / SOL), an amount (presets or
/// custom), send, then a thank-you state.
class _TipSheet extends StatefulWidget {
  final TipConfig config;
  const _TipSheet({required this.config});

  @override
  State<_TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<_TipSheet> {
  late TipToken _token;
  late String _amount;
  bool _sending = false;
  bool _done = false;
  String? _error;

  final TextEditingController _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Tokens and their limits come from the native layer; this sheet keeps no
    // copy that could disagree with what the transaction enforces.
    _token = widget.config.tokens.first;
    // Smallest preset, not the largest: a tip is a thank-you, and the default
    // should not nudge upward.
    _amount = _token.presets.first;
    _field.text = _amount;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _onToken(TipToken t) {
    setState(() {
      _token = t;
      _amount = t.presets.first;
      _field.text = _amount;
      _field.selection = TextSelection.collapsed(
        affinity: TextAffinity.upstream,
        offset: _amount.length,
      );
      _error = null;
    });
  }

  Future<void> _send() async {
    final amt = double.tryParse(_amount);
    if (amt == null || !amt.isFinite || amt <= 0) {
      setState(() => _error = "Enter a valid amount");
      return;
    }
    if (amt < _token.min) {
      setState(() => _error = "Minimum tip is ${_token.minLabel} ${_token.symbol}");
      return;
    }
    if (amt > _token.max) {
      setState(() => _error = "Maximum tip is ${_token.max} ${_token.symbol}");
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final err = await WalletAuthService.instance.sendTip(
        token: _token.symbol, amountHuman: amt);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (err == null) {
        _done = true;
      } else {
        _error = err;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.78),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      // Lift the sheet above the keyboard so the amount field stays visible.
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + keyboard),
      child: SingleChildScrollView(child: _body()),
    );
  }

  Widget _body() {
    if (_done) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 48, color: VisorTheme.primary),
            const SizedBox(height: 16),
            const Text(
              "Thank you for supporting Visor",
              style: TextStyle(
                color: VisorTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Your tip went straight to the developer wallet. "
              "This keeps Visor free and private for everyone.",
              style: const TextStyle(color: VisorTheme.textDim, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Done"),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          "Send a tip",
          style: TextStyle(
            color: VisorTheme.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Straight to the developer. Choose a token and amount.",
          style: TextStyle(color: VisorTheme.textDim, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final t in widget.config.tokens)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.symbol),
                    selected: _token.symbol == t.symbol,
                    onSelected: (_) => _onToken(t),
                    labelStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          "Amount (${_token.symbol})",
          style: const TextStyle(color: VisorTheme.textDim, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final p in _token.presets)
               ActionChip(
                 label: Text(p),
                 onPressed: () => setState(() {
                   _amount = p;
                   _field.text = p;
                   _error = null;
                 }),
               ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _field,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            setState(() {
              _amount = v;
              _error = null;
            });
          },
          style: const TextStyle(color: VisorTheme.text, fontSize: 16),
          decoration: InputDecoration(
            hintText: "Custom amount (${_token.symbol})",
            filled: true,
            fillColor: VisorTheme.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: VisorTheme.danger, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VisorTheme.bg,
                    ),
                  )
                : const Icon(Icons.send, size: 18),
            label: Text(_sending ? "Waiting for Seed Vault…" : "Send tip"),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "A Seed Vault window will open — review and confirm the exact "
          "amount before it goes out. You are in full control.",
          style: TextStyle(color: VisorTheme.textDim, fontSize: 12, height: 1.3),
        ),
      ],
    );
  }
}

/// Show the tip sheet (full screen, so the Seed Vault deep-link can return).
void showTipSheet(BuildContext context, TipConfig config) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TipSheet(config: config),
  );
}