import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../core/theme/visor_theme.dart";

/// About / Support screen: what Visor does, the publisher Solana address
/// (copyable), and a note that the app is free. Fits on one screen, no scroll.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String _solAddress =
      "H2gnCCWcAtjgRYVPdCLv37zFdPu4TsdlwfMzvedKXW5w";
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: _solAddress));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Visor trains your visual cortex with Gabor-patch games and "
                "guided eye exercises. No paywall, no ads, no accounts — all "
                "data stays on your device.",
                style: TextStyle(color: VisorTheme.text, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 24),
              const Text(
                "If Visor helped your eyes, a tip is appreciated — never required.",
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
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _copy,
                        icon: Icon(_copied ? Icons.check : Icons.content_copy,
                            size: 18),
                        label: Text(_copied ? "Copied" : "Copy address"),
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
