import 'package:flutter/material.dart';

import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import 'neo_surface.dart';

/// Shared scaffold for profile sub-settings screens.
class SettingsDetailScaffold extends StatelessWidget {
  const SettingsDetailScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 22, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: PaisaColors.ink,
                    ),
                  ),
                  Text(
                    title,
                    style: PaisaTheme.sora(
                      size: 22,
                      weight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: PaisaColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NeoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      radius: 16,
      borderWidth: 1.5,
      child: Column(children: children),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PaisaTheme.manrope(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: PaisaColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: PaisaTheme.manrope(
                    size: 12,
                    color: PaisaColors.mutedCaption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value ? 'ON' : 'OFF',
                style: PaisaTheme.label(
                  size: 9,
                  color: value ? PaisaColors.primary : PaisaColors.muted,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              // Material Switch (not .adaptive): theme SwitchThemeData applies.
              // Do not set activeColor — on M3 it paints thumb+track the same
              // primary lime and the handle disappears into a solid green blob.
              Switch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PaisaTheme.manrope(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: destructive
                          ? PaisaColors.overBudgetSoft
                          : PaisaColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: PaisaTheme.manrope(
                      size: 12,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: destructive
                      ? PaisaColors.overBudget.withOpacity(0.6)
                      : PaisaColors.muted,
                ),
          ],
        ),
      ),
    );
  }
}

Widget settingsDivider() =>
    const Divider(height: 1, color: PaisaColors.divider);
