// ignore_for_file: avoid_print

import 'package:paisa_app/services/sms/parsed_sms_transaction.dart';
import 'package:paisa_app/services/sms/sms_parser.dart';
import 'package:paisa_app/services/sms/sms_scan_pipeline.dart';

void main() {
  final samples = [
    (
      'AD-SBICRD-S',
      'Rs.605.29 spent on your SBI Credit Card ending 3452 at IRCTCAutoPe on 07/12/25.',
    ),
    (
      'AD-ICICIT-S',
      'Payment of Rs 14,747.00 has been received on your ICICI Bank Credit Card XX2009 through Bharat Bill Payment System on 03-DEC-25.',
    ),
    (
      'AX-IDFCFB-S',
      'Delicious Purchase! INR 80.00 spent on your IDFC FIRST Bank Credit Card ending XX7424 at HungerBox on 11 DEC 2025',
    ),
    (
      'VM-HDFCBK-S',
      'Update! INR 2,02,284.00 deposited in HDFC Bank A/c XX5300 on 28-NOV-25 for NEFT Cr-CHAS0INBX01-NetApp Salary NOV 25 NetApp India Private Limited-Amar Kumar',
    ),
    (
      'JD-ICICIT-S',
      'Dear  BELI  DEVI ,Your account  XXXXXXXX0429  has been credited with amount  2602.25 .Thanks,  LENDENCLUB BORROWER REPAYMENT ISP LTD ACCOUNT',
    ),
  ];
  for (final (sender, body) in samples) {
    final input = SmsMessageInput(
      id: '1',
      sender: sender,
      body: body,
      timestamp: DateTime.now(),
    );
    final gate = SmsScanPipeline.process(input);
    final txn = SmsParser.parseTransaction(input);
    print('---');
    print(body.substring(0, body.length.clamp(0, 80)));
    print(
      'gate=${gate.isParsed} bank=${txn?.bank} mask=${txn?.maskedAccount} credit=${txn?.isCredit}',
    );
  }
}
