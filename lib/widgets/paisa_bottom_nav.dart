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
    'HOME',
    'TRANSACTIONS',
    'BUDGET',
    'STATS',
    'YOU',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PaisaColors.surface,
        border: Border(
          top: BorderSide(color: PaisaColors.navBorder, width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_labels.length, (i) {
              final active = i == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: PaisaColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _iconFor(i),
                            size: 18,
                            color: PaisaColors.inkOnAccent,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(
                            _iconFor(i),
                            size: 18,
                            color: PaisaColors.navInactive,
                          ),
                        ),
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _labels[i],
                          maxLines: 1,
                          style: PaisaTheme.manrope(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: active
                                ? PaisaColors.primary
                                : PaisaColors.navInactive,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
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
