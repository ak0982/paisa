import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:paisa_app/providers/app_settings.dart';
import 'package:paisa_app/providers/finance_store.dart';
import 'package:paisa_app/theme/paisa_theme.dart';

/// Wraps a widget with providers used across settings/profile tests.
Widget buildTestApp({
  required Widget child,
  required AppSettings settings,
  FinanceStore? store,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<FinanceStore>.value(
        value: store ?? FinanceStore(),
      ),
      ChangeNotifierProvider<AppSettings>.value(value: settings),
    ],
    child: MaterialApp(
      theme: PaisaTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}
