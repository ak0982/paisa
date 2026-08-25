# Code Review Round 3 (Security) by Claude (Fable) — Paisa

**Repo:** `ak0982/paisa` @ `main` (schema 35, HEAD `3ac2837`) · **Date:** 25 Aug 2026
**Focus:** security / vulnerability audit of the whole application, plus review of the commits since round 2 (`fca7343` → `3ac2837`: schema 33/34/35 parser work, the native `getSmsById` reverse-lookup, and the Day Strip / Pulse Calendar / Coin Flip / Stats-coin UI).
**Method:** read the release `AndroidManifest.xml`, `android/app/build.gradle`, `android/gradle.properties`, `MainActivity.kt`, the debug/profile manifests, `pubspec.yaml`, `app_settings.dart`, `transaction_database.dart`, `.gitignore`, the regex parser (`sms_parser.dart`), and the logging paths. Every claim below is verified against the code; where a suspected issue turned out **not** to be exploitable, it is listed in §3 with the evidence, rather than dropped silently. Line numbers refer to `main` at review time.

**Round-3 verification addendum (re-checked before publishing).** I re-verified the load-bearing claims: (1) a repo-wide search confirmed **no** `allowBackup` / `fullBackupContent` / `dataExtractionRules` / backup-rules XML exists anywhere in the project (only `build.gradle`'s `targetSdkVersion flutter.targetSdkVersion` and this report match); (2) `targetSdkVersion` is **not pinned** — it resolves to the Flutter SDK default (34 for the Flutter 3.19+ implied by `sdk: '>=3.3.1'`), which changes the `adb backup` sub-vector (see SEC-1, corrected below); (3) storage locations were corrected by reading `app_settings.dart` and `transaction_database.dart` — **budgets live in the SQLite `category_budgets` table, not `shared_preferences`** (an earlier draft mis-stated this).

Threat model for this app: a purely on-device Android finance app that reads the SMS inbox, parses bank/UPI alerts, and stores parsed transactions + discovered accounts + budgets in a local SQLite DB. There is no backend and (in release) no network. So the meaningful adversaries are: (a) **another app or tooling on the same device** (screenshots, logs, backups), (b) **anyone with physical/ADB access to the device**, (c) **the device's cloud backup**, and (d) **a crafted SMS** as a remote input into the parser. This review is scoped to those.

---

## 1. Security findings (verified, ranked)

### SEC-1 (High for a finance app) — Financial data leaves the device via backup: `allowBackup` defaults to true over a plaintext DB

**Evidence.** The release manifest (`android/app/src/main/AndroidManifest.xml:3–6`) declares `<application>` with **no** `android:allowBackup="false"`, **no** `android:fullBackupContent`, and **no** `android:dataExtractionRules` (repo-wide search: none exist anywhere). Android therefore treats the app as backup-eligible (default `allowBackup=true`). The data it protects is unencrypted and all lives under the app's data dir, which Auto Backup includes by default:
- `transaction_database.dart` opens a plain `sqflite` DB (`paisa_transactions.db`) with no cipher, holding every transaction, every discovered savings/card/loan account, **and** every budget limit (`category_budgets` table);
- `shared_preferences` holds the profile name/email (`profile_user_name` / `profile_user_email`), the merchant-mask toggle, and the hidden-account masks (`app_settings.dart:15–18`).

**Impact.** The full parsed financial history — every transaction (merchant, amount, bank, masked account, category, timestamp), every discovered account, budgets, and the user's name/email — is swept off-device via:
- **Google Auto Backup** → uploaded to the user's Google Drive backup, off-device and outside the app's control. This is the **primary live vector** and applies regardless of `targetSdk`: any app with `allowBackup` unset (default true) and a backup-enabled Google account is auto-backed-up. The README's "nothing is uploaded and there is no backend" promise is technically defeated by the OS backup path the app opted into by default.
- **Device-to-device / cloud restore transfer** flows — also live.
- **`adb backup`** — *nuance, corrected*: `targetSdkVersion` here is unpinned and resolves to the Flutter default (**34**), and Android **12+ (API 31+) removed app data from the `adb backup` transport** for apps unless specially flagged. So this sub-vector is effectively **dead on modern devices** and only applies to older (≤ Android 11) devices. I'm keeping it listed for completeness but it is not the main concern — the cloud backup path is.

For an app whose entire pitch is "everything stays on your device," the cloud-backup path alone makes this the highest-value gap.

**Fix.** Set `android:allowBackup="false"` on `<application>` (simplest), **or** keep backup but add `android:dataExtractionRules` (API 31+) and `android:fullBackupContent` (API ≤30) that exclude `paisa_transactions.db` and the shared-prefs file. Best: combine `allowBackup=false` with at-rest encryption (SEC-3). No schema bump needed (manifest-only).

### SEC-2 (Medium) — No `FLAG_SECURE`: balances and now raw bank SMS are exposed to screenshots / recents / screen-recording

**Evidence.** `MainActivity.kt` never sets `window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)` (the file is the full activity; there is no such call). Round-3 added the Coin Flip "reverse" feature that fetches and displays the **original bank SMS** (`getSmsById`, `MainActivity.kt:77–97, 132–154`; commit `c5641b1` "Show original bank SMS on Coin Flip").

**Impact.** Without `FLAG_SECURE`, the OS renders the app content into the **recent-apps thumbnail**, and any screenshot / screen-recording (including other apps using MediaProjection, or `adb shell screencap`) captures whatever is on screen — account balances, transaction lists, and now the verbatim bank alert SMS (sender + body). For a finance app this is a standard hardening expectation.

**Fix.** Add `FLAG_SECURE` in `MainActivity.onCreate` (optionally behind a user setting, since it also blocks legitimate screenshots). Cheap, one line.

### SEC-3 (Medium) — At-rest plaintext database and no app lock (previously deferred as ISSUE-15)

**Evidence.** `transaction_database.dart` uses `sqflite` with no SQLCipher; there is no `local_auth` / biometric gate anywhere in `lib/`. AGENTS.md §6 explicitly marks this as intentionally deferred ("no biometric app lock, DB still plaintext `sqflite`"). I'm restating it because from a *vulnerability* standpoint it is the load-bearing weakness the other items compound: a rooted device, malware with a privilege escalation, a backup extraction (SEC-1), or simply an unlocked/borrowed phone yields the complete financial history in cleartext at `/data/data/com.paisa.paisa_app/databases/`.

**Fix.** For any distribution beyond personal use: `sqflite_sqlcipher` for at-rest encryption + `local_auth` biometric/PIN gate on launch and on resume. Honest to keep deferred for a personal build, but it should block "productizing."

### SEC-4 (Low) — `debugPrint` runs in release builds and writes exception + stack to logcat

**Evidence.** The scan-failure handler logs `debugPrint('FinanceStore: SMS scan failed: $e'); debugPrintStack(stackTrace: stackTrace);` (`finance_store.dart:645–646`). Flutter's `debugPrint`/`debugPrintStack` are **not** compiled out of release builds — they write to the platform log (logcat).

**Impact.** Anything reading logcat (ADB over USB, an OEM logging service, or an app holding `READ_LOGS` on older/rooted devices) sees the exception text and stack. Today `$e` is a `PlatformException` whose message originates from the Kotlin channel (`SMS_SCAN_FAILED`, `e.message` of a content-provider error — `MainActivity.kt:70–73`), so it's unlikely to contain full SMS bodies, but it can leak provider error strings and internal structure, and the pattern invites future PII-in-logs regressions.

**Fix.** Gate logging on `kDebugMode` (`if (kDebugMode) debugPrint(...)`) or route through a logger that is a no-op in release.

### SEC-5 (Low) — `getSmsById` widens SMS-body exposure into the Dart/UI layer

**Evidence.** New in this round: `getSmsById` reads an arbitrary inbox row by `_ID` and returns `{id, sender, body, timestamp}` across the MethodChannel to Dart (`MainActivity.kt:77–97, 132–154`), where Coin Flip renders the raw alert.

**Assessment.** On-device only, gated by `READ_SMS`, and the `_ID` comes from the app's own stored `smsId` (passed as a parameterized `?` selection arg — no injection). The MethodChannel is **in-process** (registered on the engine's binary messenger, not an exported `<service>`), so there is **no cross-app IPC exposure** — I checked this specifically. The residual risk is only that SMS bodies, which previously never left native code, now live transiently in Dart memory and on screen, which is why SEC-2 (FLAG_SECURE) matters more now. No fix required beyond SEC-2; noted for completeness.

### SEC-6 (Low / hardening) — Release APK is unminified and unobfuscated

**Evidence.** `build.gradle:86–87` sets `minifyEnabled false` and `shrinkResources false` for `release`.

**Impact.** No R8 shrinking/obfuscation → the APK is larger and trivially reverse-engineered. Low security relevance here because there are no embedded secrets or API keys (verified: no network, no keys committed), but obfuscation is standard finance-app hygiene and shrinks the binary.

**Fix.** Enable R8 (`minifyEnabled true`, `shrinkResources true`) with a Flutter-appropriate `proguard-rules.pro`; verify the SMS platform-channel and sqflite still work post-shrink.

### SEC-7 (Info) — Broad READ_SMS scope: every SMS crosses the channel

**Evidence.** `scanInboxBatch` returns **`allRows`** — every inbox message in the page, not just bank candidates — to Dart (`MainActivity.kt:192, 201`), and `AccountDiscovery.discover` runs over all of them. The native pre-filter only decides `candidates`; `allRows` is sent regardless.

**Assessment.** Inherent to reading the inbox and fully disclosed, so not a "vulnerability," but it means the entire SMS inbox (OTPs, personal messages) is copied into the Dart heap each scan. Minimizing what crosses the boundary (e.g. only send rows that pass a cheap financial-sender/keyword gate, keep discovery native, or drop bodies once discovery is done) reduces the blast radius of any future Dart-side logging/crash-reporting.

---

## 2. New-commit review (schema 33–35 + UI), security lens

- **`getSmsById` / Coin Flip reverse** — covered by SEC-5; the "harden empty/error reverse paths" work (`c5641b1`) correctly returns `null` for a deleted SMS and renders it as an empty state rather than an error (`MainActivity.kt:132–139`), which is good defensive handling.
- **Schema 33/34/35 parser changes** (ICICI refunds, debit-card BBPS as savings, same-source Spent-vs-ALERT twin collapse) — reviewed as parsing/classification logic; no new native permissions, no network, no injection surface. These are correctness changes, not security-relevant, and out of scope for this pass (round-2 covered the classification-correctness angle).
- **Day Strip / Pulse Calendar / Stats coin** — pure Flutter UI over already-stored data; no new capability, storage, or export path introduced.

No new commit introduced a network call, a new permission, an exported component, or a secret.

---

## 3. Explicitly checked and **NOT** vulnerabilities (rigor / no false alarms)

I tested each of these rather than assume, so they are not in the findings above:

- **ReDoS via crafted SMS — NOT exploitable.** The parser runs a large regex alternation over untrusted SMS bodies, so I scanned every pattern for catastrophic backtracking. The only unbounded-quantifier construct is `spent using (?:\w+\s+)+bank card` (`sms_parser.dart:104`, inside `_completedTxnPattern`). I timed it against 500–4000-token non-matching inputs: **0.1–0.2 ms, flat** (linear). Reason: `\w` and `\s` are disjoint character classes, so a run of "word word …" has exactly one valid tiling into `\w+\s+` iterations — there is no ambiguity for the engine to backtrack over. Bounded siblings (`(?:\w+ ){0,4}`, `{0,3}`) are inherently safe. No catastrophic pattern exists in the parser. *(Minor hygiene: bounding the one `+` to `{0,6}` would make it obviously safe to future readers — not a vulnerability.)*
- **SQL injection into the SMS content provider — NOT present.** Every `contentResolver.query` uses parameterized `?` selection args (`MainActivity.kt:111–118, 136–138, 228–234, 248–251`). The only string interpolation is `LIMIT $limit OFFSET $offset` (`:250`), where `limit`/`offset` are `Int`s from Dart, never attacker-controlled strings.
- **Cross-app IPC exposure — NOT present.** The `com.paisa.paisa_app/sms` MethodChannel is registered in-process on the Flutter engine; there is no exported `<service>`/`<provider>`/`<receiver>`. The only exported component is the launcher `MainActivity` (`exported="true"` with a MAIN/LAUNCHER filter only — standard and required).
- **Committed secrets — NONE.** No keystore, `key.properties`, `.env`, or API key is in the repo; `.gitignore` excludes `*.jks`, `*.keystore`, `**/key.properties`, and all SMS dumps / analysis DBs. `build.gradle:80–84` **fails closed** — release builds throw if the keystore is absent, so no accidental debug-signed release (commit `7f01fca`).
- **Network / exfiltration surface — NONE in release.** `INTERNET` is declared only in `android/app/src/debug/AndroidManifest.xml` and `.../profile/AndroidManifest.xml` (Flutter tooling), **not** in the release `main` manifest. `pubspec.yaml` has no HTTP/analytics/crash-reporting/Firebase dependency. `flutter_svg` parses only bundled `assets/banks/` SVGs, not remote input. This is a genuine strength and materially shrinks the threat model.
- **Signing config — sound.** V1+V2+V3 enabled, keystore-gated, no debug fallback.

---

## 4. Prioritized security actions

1. **SEC-1** — `android:allowBackup="false"` + data-extraction rules excluding the DB/prefs (manifest-only; highest impact, lowest effort).
2. **SEC-2** — `FLAG_SECURE` (one line; now more important because Coin Flip surfaces raw SMS).
3. **SEC-3** — SQLCipher + biometric lock before any non-personal distribution.
4. **SEC-4** — gate `debugPrint`/`debugPrintStack` on `kDebugMode`.
5. **SEC-6/SEC-7** — enable R8; trim what crosses the SMS channel.

## 5. Verdict

The app's network-free, on-device architecture, fail-closed release signing, parameterized provider queries, disciplined `.gitignore`, and (verified) ReDoS-free parser make the *code-level* attack surface genuinely small — better than most finance apps at this stage. The real exposure is at the **platform boundary**: the app opts into OS cloud backup by default over a plaintext database (SEC-1), leaves its screens (now including raw bank SMS) screenshot- and recents-exposed (SEC-2), and keeps data unencrypted at rest with no app lock (SEC-3). All three are standard, well-understood Android hardening steps and none require architectural change — SEC-1 and SEC-2 are a handful of lines. Fixing them closes the gap between the app's "everything stays private on your device" promise and what the platform actually does with its data by default.
