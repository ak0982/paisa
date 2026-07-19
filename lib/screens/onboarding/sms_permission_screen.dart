import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/gradient_button.dart';
import '../main_shell.dart';
import 'ready_screen.dart';

class SmsPermissionScreen extends StatelessWidget {
  const SmsPermissionScreen({super.key});

  Future<void> _allowSms(BuildContext context) async {
    await Permission.sms.request();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ReadyScreen()),
    );
  }

  void _skip(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 16, 26, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: PaisaColors.dividerAlt,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      fixedSize: const Size(40, 40),
                    ),
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  const _StepIndicator(activeIndex: 2),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 26),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE7F5EC), Color(0xFFD4EEDD)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 42,
                    color: PaisaColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Allow SMS access',
                textAlign: TextAlign.center,
                style: PaisaTheme.sora(
                  size: 23,
                  weight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Paisa reads your bank alert messages to find and categorise transactions automatically.',
                textAlign: TextAlign.center,
                style: PaisaTheme.manrope(
                  size: 13.5,
                  color: PaisaColors.muted,
                ),
              ),
              const SizedBox(height: 22),
              _PrivacyCard(),
              const Spacer(),
              GradientButton(
                label: 'Allow SMS Access',
                onPressed: () => _allowSms(context),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _skip(context),
                child: Text(
                  'Skip for now',
                  style: PaisaTheme.manrope(
                    size: 14,
                    weight: FontWeight.w600,
                    color: PaisaColors.mutedLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      'Messages are processed on your device — never uploaded to any server.',
      'We read bank alerts only. Personal messages are ignored.',
      'Your data is never sold or shared with anyone.',
    ];

    return Container(
      decoration: BoxDecoration(
        color: PaisaColors.card,
        border: Border.all(color: PaisaColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F0E7),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: PaisaColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Your privacy is guaranteed',
                  style: PaisaTheme.manrope(
                    size: 14,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: PaisaColors.dividerAlt),
          ...items.map((text) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 16),
                      const Text(
                        '✓',
                        style: TextStyle(
                          color: PaisaColors.credit,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          text,
                          style: PaisaTheme.manrope(
                            size: 12.5,
                            color: const Color(0xFF42524A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
                if (text != items.last)
                  const Divider(height: 1, color: PaisaColors.dividerAlt),
              ],
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final active = i == activeIndex;
        return Container(
          width: active ? 22 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3.5),
          decoration: BoxDecoration(
            color: active ? PaisaColors.credit : const Color(0xFFCBD6CE),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
