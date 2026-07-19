import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/settings_detail_scaffold.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _supportEmail = 'support@paisa.app';

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: 'Help & Support',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FaqCard(
            question: 'How does Paisa detect transactions?',
            answer:
                'Paisa reads bank and UPI alert SMS on your phone, filters out promos and OTPs, then extracts amount, merchant, and date using on-device rules. Nothing leaves your phone.',
          ),
          const SizedBox(height: 12),
          _FaqCard(
            question: 'Why is SMS permission required?',
            answer:
                'Android only allows apps to read SMS after you grant permission. Without it, Paisa cannot auto-import your spending from bank alerts.',
          ),
          const SizedBox(height: 12),
          _FaqCard(
            question: 'How do I refresh my data?',
            answer:
                'Go to Profile → Rescan SMS. Paisa will scan your inbox again and add any new transactions it finds.',
          ),
          const SizedBox(height: 12),
          _FaqCard(
            question: 'Are personal chats read?',
            answer:
                'No. Paisa ignores messages from non-bank senders and skips OTPs, delivery updates, and marketing offers.',
          ),
          const SizedBox(height: 20),
          Text(
            'Contact us',
            style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              SettingsActionRow(
                title: _supportEmail,
                subtitle: 'Tap to copy support email',
                onTap: () => _copyEmail(context),
                trailing: const Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: PaisaColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Paisa · version 1.0.0',
              style: PaisaTheme.manrope(
                size: 11.5,
                color: const Color(0xFFAAB8AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Support email copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PaisaColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PaisaColors.dividerAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: PaisaTheme.manrope(
              size: 13.5,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            answer,
            style: PaisaTheme.manrope(
              size: 12.5,
              color: PaisaColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
