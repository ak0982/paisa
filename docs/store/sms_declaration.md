# Play Console — SMS permissions declaration notes

My Paisa declares **`READ_SMS`** only (no `RECEIVE_SMS` / `SEND_SMS` / `WRITE_SMS`).

Google Play requires a **Permissions declaration** for SMS (and often a short **demo video**) when an app uses SMS APIs outside narrow exceptions.

## Core use case (what to select / describe)

**Core functionality:** Personal finance / expense tracking driven by **bank and UPI transactional SMS alerts**.

Suggested declaration text (adapt to the current Play form wording):

> My Paisa is a personal finance app. Its core feature is automatically building a spending and income ledger from bank and UPI alert SMS already on the user’s device. The app requests READ_SMS, scans the inbox on-device, filters for financial alerts, and stores structured transaction fields locally. It does not send or receive SMS, does not sync SMS to a My Paisa server, and does not use SMS for account verification OTP flows as its primary purpose.

## What reviewers should see in a demo video

Record a short screencast (typically 30–90 seconds) showing:

1. Fresh launch / onboarding explaining **why SMS is needed**
2. System SMS permission prompt — user grants
3. Scan / Home filling with transactions from bank alerts
4. Opening a transaction and (optional) Coin Flip reverse showing an original bank alert
5. Privacy screen: mask merchants, clear local data, link to privacy policy
6. Voiceover or captions: “SMS stays on the device; only financial alerts become transactions”

Do **not** show unrelated personal chat threads as stored transactions.

## Related store assets

- Privacy policy: host `docs/privacy_policy.md`
- Listing copy: `docs/store/short_description.txt`, `docs/store/full_description.md`
- Data safety draft: `docs/store/data_safety.md`

## Package / version for upload

- Application id: `com.paisa.paisa_app`
- Build: `flutter build appbundle --release`
- Output: `build/app/outputs/bundle/release/app-release.aab`
