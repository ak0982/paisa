// ignore_for_file: avoid_print
import 'dart:io';
import 'package:paisa_app/services/sms/account_discovery.dart';
import 'analyze_sms_export.dart' show parseAdbSmsExport;

void main() {
  final messages = parseAdbSmsExport(
    File('${Platform.environment['HOME']}/Downloads/my_sms.txt').readAsStringSync(),
  );
  final counts = <String, int>{};
  for (final msg in messages) {
    final d = AccountDiscovery.discover(sender: msg.sender, body: msg.body);
    if (d == null) continue;
    counts[d.key] = (counts[d.key] ?? 0) + 1;
  }
  for (final e in counts.entries.where((e) => e.key.contains('3452')).toList()) {
    print('${e.value} ${e.key}');
  }
  print('total keys=${counts.length}');
  final sbiCards = counts.entries.where((e) => e.key.contains('SBI') && e.key.contains('creditCard')).toList()
    ..sort((a,b)=>b.value.compareTo(a.value));
  for (final e in sbiCards.take(10)) print('${e.value} ${e.key}');
}
