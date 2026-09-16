import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/visor_theme.dart';
import '../core/wallet/wallet_auth.dart';

/// About / Support screen: what Visor does, copy address, donate via Seed Vault.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _openTip(BuildContext context) {
    showTipSheet(context);
  }

  void _copy(BuildContext context) {
    const address = 'H2gnCCWcAtjgRYVPdCLv37zFdPu4TsdLwfMzvedKXW5w';
    Clipboard.setData(const ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address copied'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('About Visor'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Visor trains your visual cortex with Gabor-patch games and '
                'eye exercises — no ads, no tracking, no subscription.',
                style: TextStyle(color: VisorTheme.textDim, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              const Text(
                'Donate address (SOL / SKR mainnet)',
                style: TextStyle(
                  color: VisorTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'H2gnCCWcAtjgRYVPdCLv37zFdPu4TsdLwfMzvedKXW5w',
                style: const TextStyle(
                  color: VisorTheme.primary,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openTip(context),
                      icon: const Icon(Icons.volunteer_activism, size: 18),
                      label: const Text('Send a tip'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _copy(context),
                    child: const Text('Copy address', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Opens your Seed Vault wallet — the amount and token are '
                'yours to set. Nothing leaves your wallet unless you confirm.',
                style: TextStyle(color: VisorTheme.textDim, fontSize: 12, height: 1.3),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Visor — Vision Training & Eye Exercises',
                style: TextStyle(
                  color: VisorTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Built with Flutter • Solana Mobile Wallet Adapter',
                style: TextStyle(color: VisorTheme.textDim, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open source • Privacy first • No analytics',
                style: TextStyle(color: VisorTheme.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for tip: pick token (SOL/SKR), amount (presets + custom), send, then thank-you.
void showTipSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _TipSheet(),
  );
}

class _TipSheet extends StatefulWidget {
  const _TipSheet();

  @override
  State<_TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<_TipSheet> {
  String _token = 'SOL';  // Changed default to SOL
  String _amount = '0.05';
  bool _sending = false;
  bool _done = false;
  String? _error;
  bool _authorizing = false;

  static const _presets = {
    'SOL': ['0.01', '0.05', '0.1'],  // SOL first
    'SKR': ['5', '10', '50'],
  };
  static const _max = {'SOL': 1.0, 'SKR': 1000.0};  // SOL first

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

  void _onPreset(String p) {
    setState(() {
      _amount = p;
      _field.text = p;
      _error = null;
    });
  }

  Future<void> _authorizeAndSend() async {
    // First, ensure wallet is authorized
    if (!_authorizing) {
      setState(() {
        _authorizing = true;
        _error = null;
      });

      final auth = await WalletAuthService.instance.authorize();
      if (!mounted) return;

      setState(() {
        _authorizing = false;
      });

      if (auth == null) {
        setState(() {
          _error = 'Wallet authorization cancelled or unavailable';
        });
        return;
      }
    }

    // Now send the tip
    final amt = double.tryParse(_amount);
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    final cap = _max[_token]!;
    if (amt > cap) {
      setState(() => _error = 'More than the $cap $_token cap this app allows');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final err = await WalletAuthService.instance.sendTip(
      token: _token,
      amountHuman: amt,
    );

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
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.78),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + keyboardHeight,
      ),
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
              'Thank you for supporting Visor',
              style: TextStyle(
                color: VisorTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your tip went straight to the developer wallet. '
              'This keeps Visor free and private for everyone.',
              style: const TextStyle(color: VisorTheme.textDim, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
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
          'Send a tip',
          style: TextStyle(
            color: VisorTheme.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Straight to the developer. Choose a token and amount.',
          style: TextStyle(color: VisorTheme.textDim, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Token selector
        Text(
          'Token',
          style: const TextStyle(color: VisorTheme.textDim, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: _presets.keys.map((t) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(t),
                  selected: _token == t,
                  onSelected: (_) => _onToken(t),
                  labelStyle: const TextStyle(fontSize: 14),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // Amount input with presets
        Text(
          'Amount ($_token)',
          style: const TextStyle(color: VisorTheme.textDim, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presets[_token]!.map((p) {
            return ActionChip(
              label: Text(p),
              onPressed: _sending || _authorizing ? null : () => _onPreset(p),
              labelStyle: const TextStyle(fontSize: 14),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _field,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: VisorTheme.text, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Custom amount',
            hintStyle: TextStyle(color: VisorTheme.textDim),
            filled: true,
            fillColor: VisorTheme.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: VisorTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: VisorTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: VisorTheme.primary, width: 2),
            ),
            errorText: _error,
            errorStyle: const TextStyle(fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (v) => setState(() {
            _amount = v;
            _error = null;
          }),
          onSubmitted: (_) => _authorizing || _sending ? null : _authorizeAndSend(),
        ),
        const SizedBox(height: 16),

        // Send button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending || _authorizing ? null : _authorizeAndSend,
            icon: _authorizing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VisorTheme.bg,
                    ),
                  )
                : _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: VisorTheme.bg,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
            label: Text(
              _authorizing
                  ? 'Connecting to Seed Vault…'
                  : _sending
                      ? 'Waiting for Seed Vault…'
                      : 'Send tip',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A Seed Vault window will open — review and confirm the exact '
          'amount before it goes out. You are in full control.',
          style: TextStyle(color: VisorTheme.textDim, fontSize: 12, height: 1.3),
        ),
      ],
    );
  }
}