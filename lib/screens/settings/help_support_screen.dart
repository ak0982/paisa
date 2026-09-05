import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/legal.dart';
import '../../services/external_link.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../utils/app_version.dart';
import '../../widgets/settings_detail_scaffold.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: 'Help & Support',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FaqCard(
            question: 'How does My Paisa detect transactions?',
            answer:
                'My Paisa reads bank and UPI alert SMS on your phone, filters out promos and OTPs, then extracts amount, merchant, and date using on-device rules. Nothing leaves your phone.',
          ),
          const SizedBox(height: 12),
          _FaqCard(
            question: 'Why is SMS permission required?',
            answer:
                'Android only allows apps to read SMS after you grant permission. Without it, My Paisa cannot auto-import your spending from bank alerts.',
          ),
          const SizedBox(height: 12),
          _FaqCard(
            question: 'How do I refresh my data?',
            answer:
                'Go to Profile → Rescan SMS. My Paisa will scan your inbox again and add any new transactions it finds.',
          ),
          const SizedBox(height: 12),
          _FaqCard(
            question: 'Are personal chats read?',
            answer:
                'My Paisa scans your SMS inbox on-device to find bank and UPI alerts. Personal chat messages are not stored as transactions — only financial alerts that pass the filter are saved. Reading the inbox is how detection works; we do not claim we never read SMS.',
          ),
          const SizedBox(height: 20),
          Text(
            'Legal',
            style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              SettingsActionRow(
                title: 'Privacy policy',
                subtitle: 'Open the hosted privacy policy in your browser',
                onTap: () => _openPrivacyPolicy(context),
                trailing: const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: PaisaColors.primary,
                ),
              ),
            ],
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
                title: LegalUrls.supportEmail,
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
          const Center(child: AppVersionLabel()),
        ],
      ),
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final opened = await const ExternalLink().open(LegalUrls.privacyPolicyUrl);
    if (!context.mounted) return;
    if (opened) return;
    await Clipboard.setData(
      const ClipboardData(text: LegalUrls.privacyPolicyUrl),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Privacy policy URL copied — open it in a browser'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyEmail(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(text: LegalUrls.supportEmail),
    );
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
