# Paisa App (v1)

Cross-platform **Android & iOS** personal finance tracker built from the v1 design handoff in `../design_handoff_paisa/`.

Paisa automatically tracks bank SMS alerts (HDFC, SBI, ICICI, Axis, Kotak, Paytm, PhonePe) and extracts transactions with zero manual entry. **v1 now reads real SMS on Android**, parses them with regex on-device, stores them locally, and drives all screens from that data.

## Screens

- **Onboarding:** Welcome → SMS Permission → Ready
- **Home:** Dashboard with monthly summary, category chips, recent transactions
- **Transactions:** Search, category filters, date-grouped list, FAB
- **Budgets:** Overview card, per-category progress bars
- **Insights:** Spending charts, comparisons, top merchants
- **Profile:** User card, connected banks, settings

## Tech stack

- Flutter 3.x (single codebase for Android + iOS)
- Google Fonts (Sora + Manrope)
- Design tokens from v1 spec (₹ currency, emerald palette)

## Run locally

```bash
cd paisa_app
flutter pub get
flutter run          # connected device or emulator
flutter run -d ios   # iOS simulator
flutter run -d android
```

## Project structure

```
lib/
  main.dart                 # App entry + onboarding gate
  theme/                    # Colors, typography
  models/                   # Transaction, Budget, Category
  data/mock_data.dart       # v1 demo data from design spec
  screens/                  # All screens + bottom nav shell
  widgets/                  # Shared UI components
```

## Android permissions

`READ_SMS` and `RECEIVE_SMS` are declared for the SMS permission onboarding step. SMS reading is requested at runtime on Android.

## v1 SMS pipeline (Android)

1. Read inbox SMS (bank senders only)
2. Regex extract amount, merchant, account, debit/credit
3. Auto-categorize (Food, Travel, Shopping, etc.)
4. Store in SQLite (deduped by SMS id)
5. Refresh Dashboard, Transactions, Budgets, Insights, Profile

**Rescan:** pull down on Home, tap sync FAB on Transactions, or Profile → Rescan SMS.

**Note:** SMS reading is Android-only (iOS does not allow inbox access).

## Design reference

Open `../design_handoff_paisa/Paisa.dc.html` in a browser to view the original high-fidelity design canvas.
