import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_settings.dart';
import '../providers/finance_store.dart';
import '../models/bank_account.dart';
import '../services/sms/account_discovery.dart';
import '../services/sms/sms_reader_service.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import 'edit_profile_screen.dart';
import 'onboarding/welcome_screen.dart';
import 'settings/help_support_screen.dart';
import 'settings/privacy_settings_screen.dart';

enum _SettingAction { rescan, privacy, help, logout }

enum _AccountFilter { all, savings, creditCard, loan }

extension on _AccountFilter {
  String get chipLabel => switch (this) {
        _AccountFilter.all => 'All',
        _AccountFilter.savings => 'Savings',
        _AccountFilter.creditCard => 'Credit card',
        _AccountFilter.loan => 'Loan',
      };

  /// Empty-state copy shown when the selected filter has no accounts.
  String get emptyLabel => switch (this) {
        _AccountFilter.all => 'No bank accounts detected yet. Scan SMS to '
            'auto-detect accounts from your alerts.',
        _AccountFilter.savings => 'No savings accounts yet.',
        _AccountFilter.creditCard => 'No credit card accounts yet.',
        _AccountFilter.loan => 'No loan accounts yet.',
      };

  bool matches(BankAccount account) => switch (this) {
        _AccountFilter.all => true,
        _AccountFilter.savings => account.kind == AccountKind.savings,
        _AccountFilter.creditCard => account.kind == AccountKind.creditCard,
        _AccountFilter.loan => account.kind == AccountKind.loan,
      };
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  _AccountFilter _accountFilter = _AccountFilter.all;

  Future<void> _handleRescan(BuildContext context, FinanceStore store) async {
    if (store.isLoading) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await store.fullRescanFromSms();
    if (!context.mounted) return;

    if (store.error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(store.error!),
          behavior: SnackBarBehavior.floating,
          backgroundColor: PaisaColors.overBudget,
        ),
      );
      return;
    }

    final message = result.newCount > 0
        ? 'Refreshed ${result.totalCount} transactions from ${result.scannedSms} SMS'
        : 'Up to date · ${result.totalCount} transactions from ${result.scannedSms} SMS';

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: PaisaTheme.manrope(
            size: 13,
            color: PaisaColors.inkOnAccent,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: PaisaColors.primary,
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context, FinanceStore store) async {
    final appSettings = context.read<AppSettings>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Log out?',
          style: PaisaTheme.sora(size: 17, weight: FontWeight.w700),
        ),
        content: Text(
          'This clears all local transactions and returns you to the welcome screen. Your SMS inbox is not modified.',
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
              'Log out',
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
    await appSettings.clearProfile();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', false);

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  void _openSetting(
    BuildContext context,
    FinanceStore store,
    _SettingAction action,
  ) {
    switch (action) {
      case _SettingAction.rescan:
        _handleRescan(context, store);
      case _SettingAction.privacy:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PrivacySettingsScreen(),
          ),
        );
      case _SettingAction.help:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const HelpSupportScreen(),
          ),
        );
      case _SettingAction.logout:
        _handleLogout(context, store);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = context.watch<AppSettings>();
    return Consumer<FinanceStore>(
      builder: (context, store, _) {
        const settings = [
          _SettingItem(
            icon: Icons.sync,
            label: 'Rescan SMS',
            tint: PaisaColors.cardElevated,
            iconColor: PaisaColors.primary,
            action: _SettingAction.rescan,
          ),
          _SettingItem(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Settings',
            tint: PaisaColors.cardElevated,
            iconColor: PaisaColors.catShopping,
            action: _SettingAction.privacy,
          ),
          _SettingItem(
            icon: Icons.help_outline,
            label: 'Help & Support',
            tint: PaisaColors.cardElevated,
            iconColor: PaisaColors.warning,
            action: _SettingAction.help,
          ),
          _SettingItem(
            icon: Icons.logout,
            label: 'Logout',
            tint: PaisaColors.cardElevated,
            iconColor: PaisaColors.overBudget,
            isDestructive: true,
            action: _SettingAction.logout,
          ),
        ];

        final allAccounts = store.bankAccounts(
          hiddenMasks: appSettings.hiddenBankAccountMasks,
        );
        final counts = <_AccountFilter, int>{
          for (final f in _AccountFilter.values)
            f: allAccounts.where(f.matches).length,
        };
        final accounts =
            allAccounts.where(_accountFilter.matches).toList(growable: false);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile',
                style: PaisaTheme.sora(
                  size: 22,
                  weight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  );
                },
                child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PaisaColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PaisaColors.dividerAlt),
                ),
                child: Row(
                  children: [
                    Transform.rotate(
                      angle: -0.05,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: PaisaColors.primary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: PaisaColors.inkOnAccent,
                            width: 2.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          appSettings.initials,
                          style: PaisaTheme.sora(
                            size: 20,
                            weight: FontWeight.w800,
                            color: PaisaColors.inkOnAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appSettings.userName.isNotEmpty
                                ? appSettings.userName
                                : 'Your profile',
                            style: PaisaTheme.sora(
                              size: 17,
                              weight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            appSettings.userEmail.isNotEmpty
                                ? appSettings.userEmail
                                : 'Personal finance, on autopilot',
                            style: PaisaTheme.manrope(
                              size: 12.5,
                              color: PaisaColors.mutedCaption,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: PaisaColors.muted,
                      size: 20,
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your bank accounts',
                    style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: PaisaColors.cardElevated,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                    'Money in & out per account',
                    style: PaisaTheme.manrope(
                      size: 10.5,
                      weight: FontWeight.w600,
                      color: PaisaColors.credit,
                    ),
                  ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (allAccounts.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in _AccountFilter.values)
                      _FilterChip(
                        label: filter.chipLabel,
                        count: counts[filter] ?? 0,
                        active: _accountFilter == filter,
                        onTap: () => setState(() => _accountFilter = filter),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (accounts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: PaisaColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: PaisaColors.dividerAlt),
                  ),
                  child: Text(
                    _accountFilter.emptyLabel,
                    style: PaisaTheme.manrope(
                      size: 13,
                      color: PaisaColors.muted,
                    ),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: PaisaColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: PaisaColors.dividerAlt),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < accounts.length; i++) ...[
                        _BankRow(
                          account: accounts[i],
                          onHide: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Not your account?'),
                                content: Text(
                                  'Hide ${accounts[i].name} ${accounts[i].mask} from your profile? '
                                  'Transactions stay in your history.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Hide'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              await appSettings.hideBankAccount(accounts[i].mask);
                            }
                          },
                        ),
                        if (i < accounts.length - 1)
                          const Divider(
                            height: 1,
                            color: PaisaColors.divider,
                          ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Settings',
                style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: PaisaColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PaisaColors.dividerAlt),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < settings.length; i++) ...[
                      _SettingsRow(
                        item: settings[i],
                        isScanning: settings[i].action == _SettingAction.rescan &&
                            store.isLoading,
                        onTap: () =>
                            _openSetting(context, store, settings[i].action),
                      ),
                      if (i < settings.length - 1)
                        const Divider(height: 1, color: PaisaColors.divider),
                    ],
                  ],
                ),
              ),
              if (store.isLoading || store.scanProgress != null) ...[
                const SizedBox(height: 16),
                _ScanProgressCard(progress: store.scanProgress),
              ],
              const SizedBox(height: 16),
              Center(
                child: Text(
                  store.lastSyncedAt != null
                      ? 'Last synced ${store.lastSyncedAt}'
                      : 'Paisa · version 1.0.0',
                  style: PaisaTheme.manrope(
                    size: 11.5,
                    color: PaisaColors.muted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingItem {
  const _SettingItem({
    required this.icon,
    required this.label,
    required this.tint,
    required this.iconColor,
    required this.action,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final Color iconColor;
  final bool isDestructive;
  final _SettingAction action;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: active ? PaisaColors.primary : PaisaColors.cardElevated,
          border: Border.all(
            color: active ? PaisaColors.primary : PaisaColors.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$label ($count)'.toUpperCase(),
          style: PaisaTheme.manrope(
            size: 11.5,
            weight: FontWeight.w700,
            color: active ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({required this.account, this.onHide});

  final BankAccount account;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: account.color,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              account.badge,
              style: PaisaTheme.sora(
                size: 15,
                weight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: PaisaTheme.manrope(
                    size: 13.5,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  account.mask,
                  style: PaisaTheme.manrope(
                    size: 11,
                    color: PaisaColors.mutedCaption,
                  ),
                ),
                if (account.receivedTotal > 0 || account.spentTotal > 0)
                  Text(
                    _accountMoneyLine(account),
                    style: PaisaTheme.manrope(
                      size: 11,
                      weight: FontWeight.w600,
                      color: PaisaColors.mutedCaption,
                    ),
                  )
                else if (account.activityCount > 0)
                  Text(
                    '${account.activityCount} SMS alerts',
                    style: PaisaTheme.manrope(
                      size: 11,
                      weight: FontWeight.w600,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
              ],
            ),
          ),
          if (onHide != null)
            IconButton(
              tooltip: 'Not my account',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onHide,
              icon: const Icon(
                Icons.close,
                size: 18,
                color: PaisaColors.muted,
              ),
            )
          else
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: PaisaColors.credit,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Active',
                  style: PaisaTheme.manrope(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: PaisaColors.credit,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _accountMoneyLine(BankAccount account) {
  final parts = <String>[];
  if (account.receivedTotal > 0) {
    parts.add('${formatInr(account.receivedTotal)} received');
  }
  if (account.spentTotal > 0) {
    parts.add('${formatInr(account.spentTotal)} sent');
  }
  return parts.join(' · ');
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.item,
    required this.onTap,
    this.isScanning = false,
  });

  final _SettingItem item;
  final VoidCallback onTap;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final disabled = isScanning;

    return InkWell(
      onTap: disabled ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.tint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(item.icon, size: 18, color: item.iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                isScanning ? 'Scanning…' : item.label,
                style: PaisaTheme.manrope(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: item.isDestructive
                      ? PaisaColors.overBudget
                      : PaisaColors.ink,
                ),
              ),
            ),
            if (isScanning)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(PaisaColors.primary),
                ),
              )
            else
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: PaisaColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanProgressCard extends StatelessWidget {
  const _ScanProgressCard({this.progress});

  final SmsScanProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final hasTotal = p != null && p.total > 0;
    final fraction = hasTotal ? p.fraction.clamp(0.0, 1.0) : null;
    final percent = fraction != null ? (fraction * 100).round() : null;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                p?.isIncremental == true
                    ? 'Checking for new SMS'
                    : 'Scanning your SMS',
                style: PaisaTheme.sora(size: 14, weight: FontWeight.w700),
              ),
              Text(
                percent != null ? '$percent%' : '…',
                style: PaisaTheme.sora(
                  size: 15,
                  weight: FontWeight.w800,
                  color: PaisaColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: PaisaColors.dividerAlt,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(PaisaColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasTotal
                ? '${p.scanned} of ${p.total} messages · ${p.parsed} transaction(s) found'
                : 'Preparing inbox…',
            style: PaisaTheme.manrope(
              size: 12,
              color: PaisaColors.mutedCaption,
            ),
          ),
        ],
      ),
    );
  }
}
