# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Flutter personal finance app targeting Android. Uses Isar (community fork) as local DB, Riverpod for state/DI, and go_router for navigation.

## First-time setup

The `android/` platform folder and all `*.g.dart` files are **not versioned** and must be generated locally:

```bash
# 1. Generate android/ folder
flutter create . --org com.hectorruz --platforms=android

# 2. Install dependencies
flutter pub get

# 3. Generate Isar model code (*.g.dart)
dart run build_runner build --delete-conflicting-outputs
```

After `flutter create`, manually adjust `android/app/build.gradle`:
- `minSdkVersion 21` (required by ML Kit and dynamic color)

And `android/app/src/main/AndroidManifest.xml`:
- Add `CAMERA` permission and `android.hardware.camera` feature (optional)
- Add `com.google.mlkit.vision.DEPENDENCIES` meta-data with value `ocr`
- Add `USE_BIOMETRIC` permission (required by `local_auth` for the app lock)

For the app lock (`local_auth`), `MainActivity` must extend `FlutterFragmentActivity` (not `FlutterActivity`); otherwise the biometric prompt crashes.

## Common commands

```bash
flutter analyze          # lint
flutter test             # all tests
flutter test test/money_test.dart  # single test file
flutter run              # run on connected device/emulator
flutter build apk --release
dart run build_runner build --delete-conflicting-outputs  # regenerate *.g.dart after model changes
```

## Architecture

**Feature-first** structure under `lib/`:

```
lib/
  main.dart          # init Isar → SeedService → RecurringRepository.materializeDue → ProviderScope → runApp
  app.dart           # MaterialApp.router + DynamicColorBuilder + AMOLED dark theme
  core/
    db/              # IsarService (open + schemas), isarProvider
    money/           # Money value object (see below)
    router/          # go_router config + Routes constants
    theme/           # ColorScheme light/dark + AMOLED override
    icons/           # app icon constants
  data/
    models/          # 8 Isar @collection classes + enums.dart
    repositories/    # one repo per model + Riverpod providers; lookups.dart for id→entity maps
    backup_service/  # JSON import/export
    seed_service/    # default data on first launch
  features/
    home_shell.dart  # IndexedStack bottom-nav (Dashboard / Movements / Receipts / Settings)
    dashboard/       # configurable card grid
    movements/       # transaction list, filters, batch edit, recurring rules
    receipts/        # OCR scan via ML Kit (on-device)
    accounts/        # account CRUD
    categories/      # category CRUD
    settings/        # app settings, goals, dashboard config
  shared/widgets/    # AmountField, AsyncValueView, IconColorPicker
```

### State / data flow

Isar is opened once in `main()` and injected via `isarProvider.overrideWithValue(isar)`. Every repository receives `Isar` through its Riverpod provider watching `isarProvider`. Screens watch `FutureProvider`s (or `StreamProvider` wrappers around `watchLazy`) for reactive updates.

### Money handling

All monetary amounts are stored and computed as **integer cents** (`amountCents`, `totalCents`, `buyPriceCents`, …). `Money` (`lib/core/money/money.dart`) is the value object for parsing user input (`Money.parseToCents`) and formatting output (`money.format()`). Never use `double` for money arithmetic.

Investment share quantities use `quantityScaled` (×10⁶ integer) to represent fractional shares without precision loss.

### Isar enums

All enums are persisted **by name** (`@Enumerated(EnumType.name)`). When adding or reordering enum values, never rely on index order. Use `enumByName()` from `lib/data/models/enums.dart` for safe parsing with a fallback instead of `.byName()` (which throws).

### Navigation

Routes are defined as constants in `Routes` (`lib/core/router/app_router.dart`). Extra data is passed via `context.go(Routes.xxx, extra: value)` and retrieved with `state.extra`. Use `_intExtra()` helper for optional int IDs.

## CI

`.github/workflows/build-apk.yml` runs on `workflow_dispatch` or pushes to `v*` tags. It regenerates `android/` and `*.g.dart` from scratch, then builds a release APK. Signed with the Flutter debug key by default — use a keystore for distribution.

To publish a release:
```bash
git tag v0.x.y && git push origin v0.x.y
```
