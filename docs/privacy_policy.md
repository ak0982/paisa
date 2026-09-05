# My Paisa Privacy Policy

**Last updated:** 31 August 2026

This privacy policy describes how **My Paisa** (`com.paisa.paisa_app`) handles information when you use the Android app.

> **Hosting:** Publish this file at the URL configured in `lib/constants/legal.dart`
> (`LegalUrls.privacyPolicyUrl`, currently `https://ak0982.github.io/paisa/privacy`).
> Until it is hosted, that URL is a placeholder — do not claim it is live in Play Console
> until GitHub Pages (or another host) serves this document.

## Summary

My Paisa is an on-device personal finance app. It reads SMS on your phone to detect bank and UPI transaction alerts, parses them locally, and stores structured transaction data in a local database. **There is no My Paisa backend.** My Paisa does not upload your SMS or transaction history to our servers.

## Information we process on your device

### SMS inbox

With your permission (`READ_SMS`), My Paisa scans your SMS inbox to find messages that look like bank or UPI alerts. The scan runs on your device. Messages that are not financial alerts (for example personal chats, OTPs, delivery updates, marketing) are filtered out and **are not stored as transactions**.

Parsed transaction fields (amount, merchant/payee text, bank name, masked account last-4, debit/credit direction, timestamp, and a reference to the SMS id) may be stored in a local SQLite database on the device. **Full SMS bodies are not written to that database.** The app can re-read an original alert from the inbox by SMS id when you open a transaction detail.

### Profile and preferences

Optional display name and email you enter, plus privacy preferences (for example merchant-name masking and screenshot blocking), are stored locally on the device (SharedPreferences / local database).

### Manual entries

If you mint a cash / off-SMS transaction inside the app, that entry is stored only on the device.

## What we do **not** do

- We do **not** operate a My Paisa cloud account or sync service.
- We do **not** sell your data.
- We do **not** use your SMS content for advertising.
- The release build does **not** request the Android `INTERNET` permission for My Paisa itself. Opening this privacy policy hands the URL to your system browser.

## Permissions

| Permission | Why |
| --- | --- |
| `READ_SMS` | Required to scan bank / UPI alert SMS and auto-build your ledger. |

My Paisa does not request `RECEIVE_SMS`, `SEND_SMS`, or `WRITE_SMS`.

## Data retention and your controls

- Data stays on your device until you clear it or uninstall the app.
- **Privacy → Clear local data** deletes My Paisa’s stored transactions and scan history. It does not modify your SMS inbox.
- You can revoke SMS permission in Android settings at any time (auto-import will stop).
- Uninstalling My Paisa removes the app’s local storage.

## Security notes

Transaction data is stored in a local plaintext SQLite database. Cloud backup and device-to-device transfer of app data are disabled in the Android manifest. Screenshot / recents protection is on by default and can be turned off in Privacy settings. Biometric app lock and encrypted storage are not currently shipped.

## Children

My Paisa is not directed at children under 13 (or the minimum age required in your country).

## Contact

Questions about this policy: **support@paisa.app**

## Changes

We may update this policy when the app’s data practices change. The “Last updated” date at the top will change when we do. Continued use of the app after an update means you accept the revised policy.
