// ignore_for_file: avoid_print
import 'package:paisa_app/services/sms/account_discovery.dart';

void main() {
  final body =
      'Dear  BELI  DEVI ,Your account  XXXXXXXX0429  has been credited with amount  2602.25 .Thanks,  LENDENCLUB BORROWER REPAYMENT';
  final d = AccountDiscovery.discover(sender: 'JD-ICICIT-S', body: body);
  print('discovered=$d');
  print('conflict=${AccountDiscovery.ownerConflictsWithProfile(d?.ownerName, "Amar Kumar")}');

  final cc = AccountDiscovery.discover(
    sender: 'AD-SBICRD-S',
    body: 'Rs.605.29 spent on your SBI Credit Card ending 3452 at IRCTCAutoPe on 07/12/25.',
  );
  print('cc=$cc');
}
