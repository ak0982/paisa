import 'package:flutter/material.dart';

import '../theme/paisa_colors.dart';
import '../widgets/paisa_bottom_nav.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'transactions_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaisaColors.surface,
      body: SafeArea(
        bottom: false,
        child: _LazyKeepAliveTabs(index: _index),
      ),
      bottomNavigationBar: PaisaBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Builds each tab on first visit and keeps the same widget instance so
/// index-only [setState] does not rebuild offstage tabs.
class _LazyKeepAliveTabs extends StatefulWidget {
  const _LazyKeepAliveTabs({required this.index});

  final int index;

  @override
  State<_LazyKeepAliveTabs> createState() => _LazyKeepAliveTabsState();
}

class _LazyKeepAliveTabsState extends State<_LazyKeepAliveTabs> {
  static const _tabCount = 5;

  final List<Widget?> _built = List<Widget?>.filled(_tabCount, null);

  Widget _createTab(int i) {
    switch (i) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const TransactionsScreen();
      case 2:
        return const BudgetsScreen();
      case 3:
        return const InsightsScreen();
      case 4:
        return const ProfileScreen();
      default:
        throw StateError('Unknown tab $i');
    }
  }

  @override
  Widget build(BuildContext context) {
    _built[widget.index] ??= _createTab(widget.index);
    return Stack(
      children: [
        for (var i = 0; i < _tabCount; i++)
          if (_built[i] != null)
            Offstage(
              key: ValueKey<int>(i),
              offstage: i != widget.index,
              child: TickerMode(
                enabled: i == widget.index,
                child: _built[i]!,
              ),
            ),
      ],
    );
  }
}
