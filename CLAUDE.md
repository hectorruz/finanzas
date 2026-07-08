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

After `flutter create`, manually adjust `android/app/build.gradle.kts`:
- `minSdkVersion 21` (required by ML Kit and dynamic color)
- Enable core library desugaring (required by `flutter_local_notifications`, or the release build fails at `checkReleaseAarMetadata`):
  ```kotlin
  compileOptions {
      isCoreLibraryDesugaringEnabled = true
  }
  dependencies {
      coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
  }
  ```

And `android/app/src/main/AndroidManifest.xml`:
- Add `CAMERA` permission and `android.hardware.camera` feature (optional)
- Add `com.google.mlkit.vision.DEPENDENCIES` meta-data with value `ocr`
- Add `USE_BIOMETRIC` permission (required by `local_auth` for the app lock)
- Register `QuickAddActivity` with `android:theme="@style/QuickAddTheme"`, `excludeFromRecents`, `taskAffinity=""`, `launchMode="singleInstance"` (the quick-add popup)
- Add `INTERNET` and `ACCESS_NETWORK_STATE` permissions (required by the LAN sync server/client — the *release* manifest by default only has `INTERNET` in `debug`/`profile`, so add it to `main`). Without `INTERNET` the sync server silently fails in release builds.
- Add `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED` permissions and register the `flutter_local_notifications` boot receiver (`ScheduledNotificationBootReceiver` + `ScheduledNotificationReceiver`) so recurring-charge reminders survive a reboot. The app uses **inexact** scheduling, so `SCHEDULE_EXACT_ALARM` is NOT needed.

For the app lock (`local_auth`), `MainActivity` must extend `FlutterFragmentActivity` (not `FlutterActivity`); otherwise the biometric prompt crashes.

For the quick-add popup (Quick Settings tile), `res/values/styles.xml` (and `values-night`) need a translucent `QuickAddTheme` (`Theme.Translucent.NoTitleBar`, `windowIsTranslucent=true`, transparent `windowBackground`). `QuickAddActivity` extends `FlutterActivity`, overrides `getDartEntrypointFunctionName()` → `"quickAddMain"` and `getBackgroundMode()` → `transparent`. `QuickAddTileService.onClick()` launches `QuickAddActivity` (not `MainActivity`).

## Common commands

```bash
flutter analyze          # lint
flutter test             # all tests
flutter test test/money_test.dart  # single test file
flutter run              # run on connected device/emulator
flutter build apk --release
dart run build_runner build --delete-conflicting-outputs  # regenerate *.g.dart after model changes
```

## Building the APK

Always commit first, then build the release APK and copy it to `~/Documentos/finanzas/`
named `finanzas-<commit>.apk`, where `<commit>` is the short hash of the commit that
produced it:

```bash
flutter build apk --release
mkdir -p ~/Documentos/finanzas
cp build/app/outputs/flutter-apk/app-release.apk \
   ~/Documentos/finanzas/finanzas-$(git rev-parse --short HEAD).apk
```

El Excel del informe se genera con `syncfusion_flutter_xlsio` (≥ 28.2.9, requerido por
`intl 0.20`). Desde la v28 **no hace falta registrar ninguna clave de licencia**
(`SyncfusionLicense.registerLicense` está deprecada); XlsIO funciona sin configuración.

### Signing (release keystore)

The release build is signed with a **stable, persistent keystore** so that every
APK can update the previous install (same signing certificate) regardless of the
machine. Config in `android/app/build.gradle.kts` reads `android/key.properties`;
if that file is missing (e.g. CI without the keystore) it falls back to the debug
key. Both the keystore and `key.properties` are **git-ignored** (`**/*.keystore`,
`android/key.properties`) and must be kept out of the repo.

- Keystore: `android/app/finanzas.keystore` (alias `finanzas`).
- `android/key.properties`: `storePassword`, `keyPassword`, `keyAlias=finanzas`,
  `storeFile=finanzas.keystore`.

**Critical:** back up `finanzas.keystore` + `key.properties` somewhere safe. If they
are lost, no future build can update an installed app — users would have to uninstall
(losing local data) and reinstall. To sign with the same identity on another machine
or in CI, copy these two files (in CI, inject them from secrets).

If the keystore ever changes (or a build was made with the debug key), Android shows
"install" instead of "update": export a JSON backup from the app, uninstall, install
the new APK, then re-import.

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
    home_shell.dart  # data-driven bottom-nav (sections chosen/ordered in settings; labelBehavior from settings)
    dashboard/       # configurable card grid; AppBar eye toggles the privacy mode
    movements/       # transaction list, filters, batch edit, recurring rules; FAB + small scan-ticket FAB
    receipts/        # OCR scan via ML Kit (on-device)
    accounts/        # account CRUD with unlimited-depth subaccounts (Account.parentId)
    categories/      # category CRUD with unlimited-depth subcategories (Category.parentId)
    settings/        # app settings, goals (planning), dashboard config, nav config
    security/        # app lock gate + device-credential auth (local_auth)
    quick_add/       # translucent popup for the Quick Settings tile (own entrypoint)
  shared/widgets/    # AmountField, AsyncValueView, IconColorPicker, MoneyText
  assets/fonts/      # Noto Sans (bundled so report PDFs render the € glyph)
```

### Quick-add popup (second Flutter entrypoint)

The Quick Settings tile opens a translucent popup to add only an income/expense, without launching the full app or passing the app lock. It runs a **separate Dart entrypoint** `quickAddMain` (`lib/main.dart`, annotated `@pragma('vm:entry-point')`) that opens Isar and runs `QuickAddPopupApp` (`lib/features/quick_add/`) — it does **not** mount `FinanzasApp`/`AppLockGate`. Android side: `QuickAddActivity` + `QuickAddTheme` (see setup). The popup reuses the app's theme via `DynamicColorBuilder` + `AppTheme`. Runs in its own engine/isolate; Isar supports multi-isolate access to the same instance.

### Sincronización LAN (admin/vinculado)

Sincroniza los datos entre dos dispositivos por Wi-Fi local, sin nube ni cuentas
(`lib/features/sync/`). Principio innegociable: **ningún cambio se sobrescribe ni
se descarta en silencio**; los timestamps solo *detectan* qué cambió, y los
conflictos los resuelve una persona en la pantalla de revisión.

Base de datos (fase 1): cada entidad sincronizable (`Account`, `Category`,
`TransactionModel`, `RecurringRule`, `Receipt`, `Goal`) implementa `Syncable`
(`lib/core/sync/`) con `uuid` (clave lógica estable entre dispositivos, los `Id`
autoincrement no sirven), `updatedAt` y `deletedAt` (tombstone: los borrados se
propagan como marca, nunca como DELETE). `MigrationService` hace el backfill
idempotente en `IsarService.open()`. Los repositorios sellan en cada `save`
(`stampForSave`) y convierten los borrados en soft-delete; toda lectura filtra
`deletedAt == null`.

Motor (fase 2, `sync_engine.dart`, sin red): `SyncCodec` traduce las FKs int
locales a uuids y de vuelta; `classifyChanges` reparte lo entrante en
nuevos / actualizaciones limpias / conflictos; `mergeAsAdmin` aplica las
decisiones de forma **atómica** (dos fases para resolver FKs hacia adelante; el
watermark del par solo avanza dentro de la misma `writeTxn`) y devuelve el estado
autoritativo; `reconcileAsLinked` lo adopta y revierte lo denegado (una alta
denegada se materializa como tombstone en ambos). `SyncPeer` guarda el par y su
watermark; `AppSettings.syncDeviceId/syncIsAdmin/syncDeviceName` son locales (no
se sincronizan ni se respaldan).

Transporte (fase 3, `lib/features/sync/net/`): el admin levanta un servidor HTTP
con `dart:io` `HttpServer` (`LanSyncServer`); el vinculado es cliente `http`
(`LanSyncClient`). Emparejamiento por PIN de 6 dígitos (`POST /pair`, sin token)
que devuelve un token; **toda otra petición exige `Authorization: Bearer <token>`**
o responde 401. Flujo: el vinculado envía su changelog (`POST /sync/changelog`),
el admin abre una `ReviewSession`, la persona revisa y confirma, y el vinculado
sondea (`GET /sync/session/{id}`) hasta recoger el estado autoritativo. La UI
(`sync_screen.dart` + `sync_review_screen.dart`) vive en Ajustes → Sincronización.
El tráfico es **HTTP plano en la LAN (sin cifrar)**: aceptable en red doméstica,
protegido por token; queda pendiente TLS autofirmado.

**De verdad bidireccional:** si el changelog entrante clasifica vacío (el
vinculado no trae altas/actualizaciones/conflictos — solo quiere ponerse al
día), `LanSyncServer._handleChangelog` **auto-finaliza la sesión en el momento**
en vez de abrir una `ReviewSession` pendiente que exige un tap del admin. Así
los cambios que solo existen en el admin llegan al vinculado con un único
"Sincronizar ahora" suyo, sin depender de que alguien note y confirme una
sesión vacía. Solo se pide revisión humana cuando hay algo real que decidir.

**Dispositivos guardados y QR:** `SyncPeer` (vinculado: `remoteIsAdmin=true`;
admin: `remoteIsAdmin=false`) persiste el emparejamiento (token + `lastAddress`),
así que la pantalla de sync no vuelve a pedir IP/puerto/PIN — el vinculado ve
sus admins guardados (`savedAdminPeersProvider`) y el admin sus vinculados
(`linkedPeersProvider`), ambos con una acción "olvidar" (borra el `SyncPeer`;
en el admin revoca el token al instante). El QR del admin (`finanzas-sync:
host=..;port=..;pin=..`, `_PairingInfo`) se puede escanear desde el vinculado
(`qr_scan_screen.dart` + `mobile_scanner`, parseo puro en `net/sync_qr.dart`)
en vez de teclearlo.

**Recordatorio + auto-sync silencioso:** el admin puede programar un aviso
local diario o en días concretos (`AppSettings.syncReminder*`, local, no se
sincroniza ni se respalda; `SyncReminderService` + `sync_reminder_planner.dart`)
que al tocarlo abre la pantalla de sync. El vinculado, en cambio, intenta
sincronizar solo (silencioso, mejor esfuerzo) al abrir o reanudar la app
(`LinkedSyncService.tryBackgroundSyncAll`, `app.dart`), para no depender de que
la persona entre a propósito a la pantalla de sync cada vez. Ambas features de
notificación comparten un único plugin/inicialización
(`core/notifications/local_notifications.dart`): `RecurringNotificationService`
y `SyncReminderService` cancelan **solo sus propios ids** (nunca `cancelAll()`)
para no pisarse la programación entre sí.

**Caveat (foreground service):** hoy el servidor corre dentro del proceso de la
app (`dart:io`), así que solo vive con la app en primer plano. El auto-sync
silencioso del vinculado tiene la misma limitación: solo dispara si su app está
abierta (aunque sea en segundo plano) en el momento del intento — con la app
totalmente cerrada no hay nada corriendo que reaccione al aviso del admin. Para
un sync realmente en segundo plano con la pantalla apagada hace falta un
**foreground service** (p. ej. `flutter_foreground_task`) con notificación
persistente y permisos `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC`; es
el siguiente paso de integración nativa. En iOS los servidores en segundo plano
están muy restringidos.

### Webapp de escritorio (fase 4)

Usar la app desde el ordenador (`lib/features/web/`, entrypoint `lib/main_web.dart`).
Es una app Flutter **web aparte**: no abre Isar ni monta `FinanzasApp`; habla con
el móvil por HTTP con `WebApiClient`, reutilizando el emparejamiento por PIN del
sync para obtener el token. Está **desacoplada de Isar** (DTOs planos en
`web_models.dart`; solo reutiliza `enums.dart` y `Money`, que son Dart puro) para
poder compilar al target web.

La API de datos vive en el servidor del móvil bajo `/api/*` (`data_api.dart`,
protegida por token) y reutiliza los repositorios de la app, así que las altas y
borrados desde la web pasan por el **mismo camino de escritura** (sellado de sync,
soft-delete) que la UI del móvil. `LanSyncServer` añade CORS y puede servir un
build web estático si se le pasa `webRoot` (`build/web`); por defecto el móvil
sirve **solo la API** y la webapp se ejecuta en el PC apuntando a la IP del móvil.

Generar el target y ejecutar/compilar la webapp:
```bash
flutter create . --platforms=web           # genera web/ (no versionado)
flutter run -d chrome -t lib/main_web.dart  # desarrollo (apunta a la IP del móvil)
flutter build web -t lib/main_web.dart      # build en build/web
```

### Notificaciones de recurrentes (fase 5)

Avisos locales de próximos cargos/ingresos recurrentes (`lib/features/notifications/`).
Cada `RecurringRule` guarda `notifyEnabled`, `notifyDaysBefore` (0 = mismo día,
1 = día antes, N = personalizada) y `notifyHour`/`notifyMinute`, configurables en
el editor de recurrentes. El aviso es **pasivo** (solo informa): el cargo se
materializa siempre automáticamente vía `materializeDue`, sin confirmación.

La lógica de fechas es pura y testeable (`notification_planner.dart`:
`computeNotifyTime` + `planNotifications`, solo avisos futuros). El plugin
(`flutter_local_notifications` + `timezone`/`flutter_timezone`) vive en
`notification_service.dart`: `rescheduleAll()` cancela y reprograma el próximo
aviso de cada regla (id de notificación = id de regla, sin duplicados) con
programación **inexacta** (no requiere `SCHEDULE_EXACT_ALARM`). Se reprograma en
`main()` (sin bloquear el arranque) y al guardar/borrar una regla.

### OCR de tickets (fase 6)

El OCR es **on-device** (ML Kit Text Recognition) y la pantalla de escaneo es la
**revisión pre-guardado**: nada se guarda a ciegas. Sobre eso:

- **Confianza por campo**: `ParsedReceipt` lleva `merchantConfident` /
  `totalConfident` (total etiquetado "TOTAL…" = alta; fallback por puntuación =
  baja) y la fecha nula = no detectada. La pantalla resalta los campos dudosos.
- **Memoria de correcciones** (`MerchantRule` + `merchant_rule_repository.dart`):
  al guardar un ticket con categoría se recuerda comercio → categoría; el próximo
  ticket del mismo comercio se categoriza solo (tiene prioridad sobre la
  sugerencia por palabras clave de `suggestCategory`). Es el enganche del futuro
  motor de reglas de auto-categorización. Estado local (no se sincroniza).
- **Detección de duplicados** (`duplicate_detector.dart`, puro): antes de crear
  el gasto se busca un movimiento con mismo importe, fecha a ±1 día y comercio
  relacionado (p. ej. el auto-creado por una recurrente) y se avisa con opción de
  guardar el ticket sin gasto.
- **Imágenes**: la foto se adjunta al ticket (copia persistente) pero **no se
  sincroniza** (`imagePath` no viaja en el codec); cada dispositivo guarda las
  suyas.

### Privacy mode (hide amounts)

`AppSettings.hideAmounts` (toggled by the eye in the dashboard AppBar) masks every monetary value app-wide. Render amounts with `MoneyText` (`lib/shared/widgets/money_text.dart`), which watches `hideAmountsProvider` and shows `kHiddenAmount` when active — prefer it over `Text(Money(x).format())` for on-screen figures.

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
