# Play Console — Data safety form (draft)

Use this as a checklist when filling **App content → Data safety**. Adjust if your practices change. My Paisa has **no backend**; answers assume on-device-only processing.

## Overview answers

| Question | Suggested answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** — data is processed/collected **on device** (not sent to a My Paisa server). Be precise in the console: Google’s form treats “collected” as data transmitted off-device from your app. **If nothing leaves the device to a developer endpoint, choose the options that match “not collected / not shared” for developer servers**, while still declaring SMS access and on-device processing honestly in the policy and SMS declaration. |
| Is all user data encrypted in transit? | N/A if no developer network transfer. Opening the privacy policy uses the system browser. |
| Do you provide a way for users to request that their data be deleted? | **Yes** — Clear local data in Privacy settings; uninstall removes app storage. |

> **Important:** Google’s Data safety definitions focus on data **collected** (transmitted off-device by your app) or **shared**. My Paisa does not transmit SMS or ledger data to My Paisa servers. Still publish an accurate privacy policy and complete the **SMS / Call Log** declaration separately.

## Data types to review in the form

| Data type | Collected by My Paisa to a server? | On-device processing | Notes for reviewers / policy |
| --- | --- | --- | --- |
| SMS or MMS | **No** (not sent to My Paisa) | **Yes** — inbox scanned for bank/UPI alerts | Declare SMS permission use in Sensitive permissions / SMS declaration |
| Financial info (purchase history / transactions) | **No** | **Yes** — derived from SMS + optional manual mint | Stored in local SQLite |
| Personal info (name, email) | **No** | Optional local profile fields | User-entered, local only |
| App activity / diagnostics | **No** | N/A | No analytics SDK in release as of this draft |

## Security practices (supporting copy)

- Data processed on device
- Users can delete local data in-app
- `allowBackup="false"` + backup/extraction rules exclude app data from Auto Backup and D2D transfer
- Release APK does not hold `INTERNET` permission

## Privacy policy URL

Must be a **publicly reachable HTTPS** URL. Host `docs/privacy_policy.md` (e.g. GitHub Pages) then set:

- Play Console privacy policy field
- In-app constant `LegalUrls.privacyPolicyUrl` in `lib/constants/legal.dart` if the final URL differs
