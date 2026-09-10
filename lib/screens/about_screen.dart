import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/visor_theme.dart';
import '../core/wallet/wallet_auth.dart';

/// About / Support screen: what Visor does, how it works, privacy, a
/// medical disclaimer, and the publisher Solana address (copyable).
/// Tip/donate: a button under the address opens a sheet with token choice
/// (SKR default), preset amounts, a custom field, and a thank-you screen.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String _solAddress =
      "H2gnCCWcAtjgRYVPdCLv37zFdPu4TsdLwfMzvedKXW5w";
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: _solAddress));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _openTip() {
    showTipSheet(context);
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
              const Text(
                "Visor trains your visual cortex with Gabor-patch games and "
                "guided eye exercises — the same stimuli neuroscience uses "
                "to study vision. Regular short sessions can ease screen "
                "fatigue, sharpen focus, and loosen eye strain from long "
                "near-work.",
                style: TextStyle(color: VisorTheme.text, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                "Each card differs by a single controlled parameter — "
                "orientation, frequency, or phase — so your brain learns to "
                "tell real visual detail apart, not just guess at noise.",
                style: TextStyle(color: VisorTheme.text, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 14),
              const Text(
                "Private by design: no accounts, no ads, no trackers, no "
                "telemetry. Every session is stored locally on your device "
                "and never leaves it.",
                style: TextStyle(color: VisorTheme.text, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 14),
              const Text(
                "Visor is a training tool, not a medical device. It does not "
                "diagnose or treat any eye condition. If you experience "
                "persistent pain, double vision, or sudden vision changes, "
                "see an eye-care professional.",
                style: TextStyle(color: VisorTheme.danger, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 14),
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
                            _solAddress,
                            style: const TextStyle(
                              color: VisorTheme.text,
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
                            onPressed: _openTip,
                            icon: const Icon(Icons.volunteer_activism, size: 18),
                            label: const Text("Send a tip"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _copy,
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
  const _TipSheet();

  @override
  State<_TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<_TipSheet> {
  String _token = "SKR";
  String _amount = "10";
  bool _sending = false;
  bool _done = false;
  String? _error;

  static const _presets = {
    "SKR": ["5", "10", "50"],
    "SOL": ["0.01", "0.05", "0.1"],
  };
  static const _max = {"SKR": 1000.0, "SOL": 1.0};

  final TextEditingController _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    _field.text = _amount;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _onToken(String t) {
    setState(() {
      _token = t;
      _amount = _presets[t]!.last;
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
    if (amt == null || amt <= 0) {
      setState(() => _error = "Enter a valid amount");
      return;
    }
    final cap = _max[_token]!;
    if (amt > cap) {
      setState(() => _error = "More than the $cap $_token cap this app allows");
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final err = await WalletAuthService.instance.sendTip(
        token: _token, amountHuman: amt);
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
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.78),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(24),
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
            for (final t in _presets.keys)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _token == t,
                    onSelected: (_) => _onToken(t),
                    labelStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          "Amount ($_token)",
          style: const TextStyle(color: VisorTheme.textDim, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final p in _presets[_token]!)
              ActionChip(
                label: Text(p),
                onPressed: () => setState(() {
                  _amount = p;
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
            hintText: "Custom amount ($_token)",
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
void showTipSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TipSheet(),
  );
}