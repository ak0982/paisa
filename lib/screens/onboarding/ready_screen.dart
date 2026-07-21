import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show categorizerVersion, transactionSchemaVersion;
import '../../providers/finance_store.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/gradient_button.dart';
import '../main_shell.dart';

class ReadyScreen extends StatefulWidget {
  const ReadyScreen({super.key});

  @override
  State<ReadyScreen> createState() => _ReadyScreenState();
}

class _ReadyScreenState extends State<ReadyScreen> {
  ScanResult? _result;
  bool _scanning = true;
  String _statusText = 'Reading bank alerts and extracting transactions on your device.';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final store = context.read<FinanceStore>();
    store.addListener(_onStoreUpdate);
    final result = await store.syncFromSms();
    store.removeListener(_onStoreUpdate);
    if (!mounted) return;
    setState(() {
      _result = result;
      _scanning = false;
    });
  }

  void _onStoreUpdate() {
    if (!mounted) return;
    final store = context.read<FinanceStore>();
    final progress = store.scanProgress;
    if (progress == null || !store.isLoading) return;
    setState(() {
      if (progress.total > 0) {
        final pct = (progress.fraction * 100).round();
        final mode = progress.isIncremental ? 'Checking new' : 'Scanning';
        _statusText = '$mode ${progress.scanned} of ${progress.total} messages ($pct%)…';
      }
    });
  }

  Future<void> _goToDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    // ISSUE-7: onboarding just performed the initial full scan of the whole
    // inbox, so stamp the current versions and clear any pending launch rescan.
    // Otherwise MainShell would immediately wipe-and-rescan the data we just
    // built.
    await prefs.setInt('categorizer_version', categorizerVersion);
    await prefs.setInt('transaction_schema_version', transactionSchemaVersion);
    if (!mounted) return;
    context.read<FinanceStore>().markLaunchScanSatisfied();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [PaisaColors.primary, Color(0xFF0C4E38)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 30),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.28)),
                  ),
                  child: Center(
                    child: _scanning
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Container(
                            width: 74,
                            height: 74,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 40,
                              color: PaisaColors.primary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  _scanning ? 'Scanning your SMS…' : "You're all set!",
                  style: PaisaTheme.sora(
                    size: 27,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _scanning
                      ? _statusText
                      : _result != null && _result!.totalSms > 0
                          ? 'Scanned ${_result!.totalSms} messages and found your transactions.'
                          : 'We scanned your inbox and set everything up automatically.',
                  textAlign: TextAlign.center,
                  style: PaisaTheme.manrope(
                    size: 14,
                    color: Colors.white.withOpacity(0.82),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    _StatTile(
                      value: _scanning
                          ? '…'
                          : '${_result?.accountCount ?? 0}',
                      label: 'accounts found',
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      value: _scanning
                          ? '…'
                          : '${_result?.totalCount ?? 0}',
                      label: 'transactions',
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      value: _scanning
                          ? '…'
                          : '${_result?.categoryCount ?? 0}',
                      label: 'categories',
                    ),
                  ],
                ),
                const Spacer(),
                GradientButton(
                  label: 'Go to Dashboard',
                  isWhite: true,
                  onPressed: _scanning ? () {} : _goToDashboard,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: PaisaTheme.sora(
                size: 26,
                weight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: PaisaTheme.manrope(
                size: 11,
                weight: FontWeight.w600,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
