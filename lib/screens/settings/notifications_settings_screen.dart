import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_settings.dart';
import '../../theme/paisa_colors.dart';
import '../../theme/paisa_theme.dart';
import '../../widgets/settings_detail_scaffold.dart';

class NotificationsSettingsScreen extends StatelessWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettings>(
      builder: (context, settings, _) {
        return SettingsDetailScaffold(
          title: 'Notifications',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose which alerts you want on this device. All notifications stay local — nothing is sent to a server.',
                style: PaisaTheme.manrope(
                  size: 13,
                  color: PaisaColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              SettingsCard(
                children: [
                  SettingsToggleRow(
                    title: 'Budget alerts',
                    subtitle:
                        'Notify when a category budget crosses 80% or goes over limit.',
                    value: settings.budgetAlerts,
                    onChanged: settings.setBudgetAlerts,
                  ),
                  settingsDivider(),
                  SettingsToggleRow(
                    title: 'Weekly summary',
                    subtitle:
                        'A Sunday recap of spending, income, and top categories.',
                    value: settings.weeklySummary,
                    onChanged: settings.setWeeklySummary,
                  ),
                  settingsDivider(),
                  SettingsToggleRow(
                    title: 'SMS scan complete',
                    subtitle:
                        'Show a brief alert after rescanning your inbox.',
                    value: settings.syncCompleteAlerts,
                    onChanged: settings.setSyncCompleteAlerts,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
