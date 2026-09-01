import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/theme/visor_theme.dart';
import '../core/wallet/wallet_auth.dart';
import 'analytics_screen.dart';
import 'exercises_screen.dart';
import 'reminder_screen.dart';
import 'setup_screen.dart';
import 'about_screen.dart';

/// Home dashboard: streak, today, best, and navigation to training modes.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _streak = 0;
  int _today = 0;
  double _best = 0;
  String? _walletAddress;
  String? _walletLabel;
  bool _connecting = false;
  String _walletError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final streak = await VisionDb.instance.streak();
    final today = await VisionDb.instance.sessionsOnDay(DateTime.now());
    final best = await VisionDb.instance.bestScore();
    final acct = await VisionDb.instance.getAccount();
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _today = today;
      _best = best;
      _walletAddress = acct?['address'] as String?;
      _walletLabel = acct?['label'] as String?;
    });
  }

  Future<void> _connectWallet() async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _walletError = '';
    });
    try {
      final auth = await WalletAuthService.instance.authorize();
      if (auth == null) {
        setState(() => _walletError = 'Cancelled');
      } else {
        await VisionDb.instance.setAccount(auth.address, auth.accountLabel);
        setState(() {
          _walletAddress = auth.address;
          _walletLabel = auth.accountLabel;
        });
      }
    } catch (e) {
      setState(() => _walletError = _friendlyWalletError(e.toString()));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnectWallet() async {
    await VisionDb.instance.clearAccount();
    setState(() {
      _walletAddress = null;
      _walletLabel = null;
      _walletError = '';
    });
  }

  String _friendlyWalletError(String raw) {
    if (raw.contains('NO_WALLET')) {
      return 'No Solana wallet found. Install Seed Vault (Solana Mobile).';
    }
    if (raw.contains('AUTH_FAILED') || raw.contains('AUTH_EXCEPTION')) {
      return raw.split(':').last.trim();
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Text(
                    'VISOR',
                    style: TextStyle(
                      color: VisorTheme.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'vision training',
                    style:
                        TextStyle(color: VisorTheme.textDim, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _accountCard(),
              const SizedBox(height: 12),
              _statsRow(),
              const SizedBox(height: 24),
              _menuButton(
                icon: Icons.play_arrow,
                title: 'Start Training',
                subtitle: 'Gabor patch game — trains your visual cortex',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SetupScreen()),
                ).then((_) => _load()),
              ),
              _menuButton(
                icon: Icons.visibility,
                title: 'Eye Exercises',
                subtitle: 'Guided movements — reduces strain & coordination',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExercisesScreen()),
                ),
              ),
              _menuButton(
                icon: Icons.alarm,
                title: 'Reminder',
                subtitle: 'Daily nudge to keep your streak alive',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReminderScreen()),
                ),
              ),
              _menuButton(
                icon: Icons.insights,
                title: 'Analytics',
                subtitle: 'Score trends, session history & progress',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
                ),
              ),
              _menuButton(
                icon: Icons.info_outline,
                title: 'Support Visor',
                subtitle: 'About this app and tipping',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
              const Spacer(),
              Center(
                child: Text(
                  'Next break: train daily to build your streak',
                  style: TextStyle(
                      color: VisorTheme.textDim.withOpacity(0.7),
                      fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Version 0.1.0',
                  style: TextStyle(
                      color: VisorTheme.textDim.withOpacity(0.5),
                      fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountCard() {
    final connected = _walletAddress != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected ? VisorTheme.success : VisorTheme.surfaceAlt,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.account_balance_wallet : Icons.wallet_outlined,
                color: connected ? VisorTheme.success : VisorTheme.textDim,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                connected ? 'Seed Vault connected' : 'No wallet connected',
                style: const TextStyle(
                  color: VisorTheme.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (connected)
                TextButton(
                  onPressed: _disconnectWallet,
                  child: const Text('Disconnect',
                      style: TextStyle(color: VisorTheme.danger)),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: VisorTheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  onPressed: _connecting ? null : _connectWallet,
                  child: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF001428)),
                        )
                      : const Text('Connect'),
                ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 6),
            Text(
              _walletLabel != null && _walletLabel!.isNotEmpty
                  ? '$_walletLabel\n$_walletAddress'
                  : _walletAddress!,
              style: const TextStyle(
                color: VisorTheme.textDim,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (_walletError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _walletError,
              style: const TextStyle(color: VisorTheme.danger, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('Streak', '$_streak-day', VisorTheme.accent),
          _stat('Today', '$_today sessions', VisorTheme.text),
          _stat('Best', _best.toStringAsFixed(0), VisorTheme.success),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style:
                const TextStyle(color: VisorTheme.textDim, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: VisorTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: VisorTheme.primary, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: VisorTheme.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: VisorTheme.textDim, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: VisorTheme.textDim, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}