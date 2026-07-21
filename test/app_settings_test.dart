import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:paisa_app/providers/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('U01-U14 AppSettings preferences', () {
    test('U04 maskMerchantNames defaults to false', () async {
      final settings = await AppSettings.load();
      expect(settings.maskMerchantNames, isFalse);
    });

    test('U09 setMaskMerchantNames toggles', () async {
      final settings = await AppSettings.load();
      await settings.setMaskMerchantNames(true);
      expect(settings.maskMerchantNames, isTrue);
      final reloaded = await AppSettings.load();
      expect(reloaded.maskMerchantNames, isTrue);
    });

    test('U12 setMaskMerchantNames notifies listeners', () async {
      final settings = await AppSettings.load();
      var count = 0;
      settings.addListener(() => count++);
      await settings.setMaskMerchantNames(true);
      await settings.setMaskMerchantNames(false);
      expect(count, 2);
    });

    test('U13 load factory returns AppSettings instance', () async {
      final settings = await AppSettings.load();
      expect(settings, isA<AppSettings>());
    });

    test('U14 restores saved prefs on load', () async {
      SharedPreferences.setMockInitialValues({
        'privacy_mask_merchants': true,
      });
      final settings = await AppSettings.load();
      expect(settings.maskMerchantNames, isTrue);
    });
  });

  group('U44-U53 Local profile setup', () {
    test('U44 userName is empty and hasProfile false by default', () async {
      final settings = await AppSettings.load();
      expect(settings.userName, isEmpty);
      expect(settings.hasProfile, isFalse);
    });

    test('U45 firstName defaults to "there" when unset', () async {
      final settings = await AppSettings.load();
      expect(settings.firstName, 'there');
    });

    test('U46 initials default to "P" when unset', () async {
      final settings = await AppSettings.load();
      expect(settings.initials, 'P');
    });

    test('U47 setProfile persists name and email', () async {
      final settings = await AppSettings.load();
      await settings.setProfile(name: 'Aarav Sharma', email: 'a@b.com');
      expect(settings.userName, 'Aarav Sharma');
      expect(settings.userEmail, 'a@b.com');
      expect(settings.hasProfile, isTrue);
      final reloaded = await AppSettings.load();
      expect(reloaded.userName, 'Aarav Sharma');
      expect(reloaded.userEmail, 'a@b.com');
    });

    test('U48 firstName returns first token', () async {
      final settings = await AppSettings.load();
      await settings.setProfile(name: 'Aarav Sharma');
      expect(settings.firstName, 'Aarav');
    });

    test('U49 initials use first + last for multi-word names', () async {
      final settings = await AppSettings.load();
      await settings.setProfile(name: 'Aarav Kumar Sharma');
      expect(settings.initials, 'AS');
    });

    test('U50 initials use single letter for one-word names', () async {
      final settings = await AppSettings.load();
      await settings.setProfile(name: 'Aarav');
      expect(settings.initials, 'A');
    });

    test('U51 setProfile trims whitespace', () async {
      final settings = await AppSettings.load();
      await settings.setProfile(name: '  Aarav Sharma  ', email: '  a@b.com ');
      expect(settings.userName, 'Aarav Sharma');
      expect(settings.userEmail, 'a@b.com');
    });

    test('U52 clearProfile wipes name and email', () async {
      final settings = await AppSettings.load();
      await settings.setProfile(name: 'Aarav', email: 'a@b.com');
      await settings.clearProfile();
      expect(settings.userName, isEmpty);
      expect(settings.userEmail, isEmpty);
      expect(settings.hasProfile, isFalse);
    });

    test('U53 setProfile notifies listeners', () async {
      final settings = await AppSettings.load();
      var notified = false;
      settings.addListener(() => notified = true);
      await settings.setProfile(name: 'Aarav');
      expect(notified, isTrue);
    });
  });
}
