import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_app/utils/bank_assets.dart';

void main() {
  group('BankAssets', () {
    test('maps canonical bank codes to SVG assets', () {
      expect(BankAssets.assetPathFor('SBI'), 'assets/banks/sbi.svg');
      expect(BankAssets.assetPathFor('HDFC'), 'assets/banks/hdfc.svg');
      expect(BankAssets.assetPathFor('ICICI'), 'assets/banks/icici.svg');
      expect(BankAssets.assetPathFor('Axis'), 'assets/banks/axis.svg');
      expect(BankAssets.assetPathFor('Kotak'), 'assets/banks/kotak.svg');
      expect(BankAssets.assetPathFor('IDFC'), 'assets/banks/idfc.svg');
      expect(BankAssets.assetPathFor('PNB'), 'assets/banks/pnb.svg');
      expect(BankAssets.assetPathFor('Federal'), 'assets/banks/federal.svg');
      expect(BankAssets.assetPathFor('Yes Bank'), 'assets/banks/yes.svg');
      expect(BankAssets.assetPathFor('IndusInd'), 'assets/banks/indusind.svg');
      expect(
        BankAssets.assetPathFor('Bank of Baroda'),
        'assets/banks/bob.svg',
      );
      expect(BankAssets.assetPathFor('Canara'), 'assets/banks/canara.svg');
      expect(BankAssets.assetPathFor('HSBC'), 'assets/banks/hsbc.svg');
    });

    test('maps aliases and account titles', () {
      expect(BankAssets.assetPathFor('SBI Savings'), 'assets/banks/sbi.svg');
      expect(
        BankAssets.assetPathFor('ICICI Credit Card'),
        'assets/banks/icici.svg',
      );
      expect(BankAssets.assetPathFor('BOB'), 'assets/banks/bob.svg');
      expect(BankAssets.assetPathFor('BOBCARD'), 'assets/banks/bob.svg');
      expect(BankAssets.assetPathFor('Yes'), 'assets/banks/yes.svg');
      expect(BankAssets.assetPathFor('IDFC FIRST'), 'assets/banks/idfc.svg');
      expect(BankAssets.assetPathFor('Fi'), 'assets/banks/federal.svg');
      expect(BankAssets.assetPathFor('Jupiter'), 'assets/banks/federal.svg');
      expect(
        BankAssets.assetPathFor('federal bank loan'),
        'assets/banks/federal.svg',
      );
      expect(BankAssets.assetPathFor('HSBC Bank'), 'assets/banks/hsbc.svg');
      expect(BankAssets.assetPathFor('HSBC Savings'), 'assets/banks/hsbc.svg');
    });

    test('is case-insensitive', () {
      expect(BankAssets.assetPathFor('sbi'), 'assets/banks/sbi.svg');
      expect(BankAssets.assetPathFor('hdfc bank'), 'assets/banks/hdfc.svg');
      expect(BankAssets.resolveSlug('AXIS'), 'axis');
    });

    test('returns null for unknown banks', () {
      expect(BankAssets.assetPathFor('LenDenClub'), isNull);
      expect(BankAssets.assetPathFor('Paytm'), isNull);
      expect(BankAssets.assetPathFor(''), isNull);
      expect(BankAssets.hasLogo('Unknown Bank'), isFalse);
    });

    test('fallbackLetter uses first alphanumeric', () {
      expect(BankAssets.fallbackLetter('SBI'), 'S');
      expect(BankAssets.fallbackLetter(''), '?');
      expect(BankAssets.fallbackLetter('***', orElse: 'B'), 'B');
    });
  });
}
