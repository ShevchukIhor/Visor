import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../core/theme/visor_theme.dart";

/// About / Support screen: what Visor does, how it works, privacy, a a
/// medical disclaimer, and the publisher Solana address (copyable).
/// Wrapped in SingleChildScrollView so it is safe on small screens.
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
