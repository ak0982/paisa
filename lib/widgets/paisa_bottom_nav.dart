import 'package:flutter/material.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';

class PaisaBottomNav extends StatelessWidget {
  const PaisaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _labels = [
    'Home',
    'Transactions',
    'Budgets',
    'Insights',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: PaisaColors.card,
        border: Border(top: BorderSide(color: PaisaColors.navBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_labels.length, (i) {
            final active = i == currentIndex;
            final color = active ? PaisaColors.credit : PaisaColors.navInactive;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_iconFor(i), size: 23, color: color),
                    const SizedBox(height: 5),
                    Text(
                      _labels[i],
                      style: PaisaTheme.manrope(
                        size: 10,
                        weight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  IconData _iconFor(int index) {
    switch (index) {
      case 0:
        return Icons.home_outlined;
      case 1:
        return Icons.receipt_long_outlined;
      case 2:
        return Icons.account_balance_wallet_outlined;
      case 3:
        return Icons.bar_chart_rounded;
      case 4:
        return Icons.person_outline;
      default:
        return Icons.circle;
    }
  }
}
