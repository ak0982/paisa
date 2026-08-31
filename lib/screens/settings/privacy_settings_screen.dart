import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../providers/app_settings.dart';
import '../../providers/finance_store.dart';
import '../../services/screen_security.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/settings_detail_scaffold.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppSettings, FinanceStore>(
      builder: (context, settings, store, _) {
        final smsGranted = store.hasSmsPermission;

        return SettingsDetailScaffold(
          title: 'Privacy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PrivacyGuaranteeCard(),
              const SizedBox(height: 16),
              SettingsCard(
                children: [
                  SettingsToggleRow(
                    title: 'Mask merchant names',
                    subtitle:
                        'Show abbreviated names in transaction lists for extra privacy.',
                    value: settings.maskMerchantNames,
                    onChanged: settings.setMaskMerchantNames,
                  ),
                  settingsDivider(),
                  SettingsToggleRow(
                    title: 'Block screenshots',
                    subtitle:
                        'Hide Paisa from screenshots, screen recording and the recent-apps preview.',
                    value: settings.blockScreenshots,
                    onChanged: (value) async {
                      await settings.setBlockScreenshots(value);
                      await const ScreenSecurity()
                          .apply(blockScreenshots: value);
                    },
                  ),
                  settingsDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SMS permission',
                                style: PaisaTheme.manrope(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                smsGranted
                                    ? 'Granted — Paisa can read bank alert SMS on this device.'
                                    : 'Not granted — transactions cannot be auto-detected.',
                                style: PaisaTheme.manrope(
                                  size: 12,
                                  color: PaisaColors.mutedCaption,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: smsGranted
                                ? PaisaColors.cardElevated
                                : PaisaColors.cardElevated,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            smsGranted ? 'Active' : 'Off',
                            style: PaisaTheme.manrope(
                              size: 10.5,
                              weight: FontWeight.w600,
                              color: smsGranted
                                  ? PaisaColors.credit
                                  : PaisaColors.overBudget,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  settingsDivider(),
                  SettingsActionRow(
                    title: 'Manage SMS permission',
                    subtitle:
                        'Open Android settings to allow or revoke SMS access.',
                    onTap: openAppSettings,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Data storage',
                style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SettingsCard(
                children: [
                  SettingsActionRow(
                    title: 'Clear local data',
                    subtitle:
                        'Delete all transactions (including minted moves) and scan history from this device. Your SMS inbox is not modified.',
                    destructive: true,
                    onTap: () => _confirmClearData(context, store),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmClearData(
    BuildContext context,
    FinanceStore store,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Clear local data?',
          style: PaisaTheme.sora(size: 17, weight: FontWeight.w700),
        ),
        content: Text(
          'This removes all transactions — including moves you minted — and scan history from Paisa. Your SMS messages will not be deleted.',
          style: PaisaTheme.manrope(size: 13.5, color: PaisaColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Clear data',
              style: PaisaTheme.manrope(
                weight: FontWeight.w600,
                color: PaisaColors.overBudget,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await store.clearAllData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Local data cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PrivacyGuaranteeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      'Messages are processed on your device — never uploaded to any server.',
      'All messages are processed on-device; only bank alerts are stored.',
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
                    color: PaisaColors.cardElevated,
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text,
                          style: PaisaTheme.manrope(
                            size: 12.5,
                            color: PaisaColors.muted,
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
        ],
      ),
    );
  }
}
