# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Mapa de la documentación:** `README.md` = qué es la app y cómo compilarla (para
personas); **este fichero** = decisiones de diseño y trampas de cada feature (la
referencia de fondo); `AGENTS.md` = arranque rápido, reglas de trabajo y pendientes
para cualquier agente de IA (Codex, Claude Code…) que retome el proyecto. Si cambias
el comportamiento de una feature, actualiza aquí su sección **en el mismo commit**.

## Project overview

Flutter personal finance app targeting Android. Uses Isar (community fork) as local DB, Riverpod for state/DI, and go_router for navigation.

## First-time setup

The `android/` platform folder **is versioned** (manifest, `build.gradle.kts`, all
Kotlin, resources — `git ls-files android/`); only `android/key.properties`,
`**/*.keystore`, `android/app/google-services.json`, `android/.gradle/` and
`android/local.properties` are git-ignored. All `*.g.dart` files are **not
versioned** and must be generated locally:

```bash
# 1. Install dependencies
flutter pub get

# 2. Generate Isar model code (*.g.dart)
dart run build_runner build --delete-conflicting-outputs
```

> **Application id is `com.example.finanzas`** (`android/app/build.gradle.kts`
> `namespace`/`applicationId`, and the Kotlin package). An earlier version of
> this doc said to regenerate `android/` with `flutter create . --org
> com.hectorruz` — **do not**: `android/` is committed, and regenerating it would
> flip the package id and break anything pinned to it (e.g. the Google Drive
> OAuth client, which is registered against `com.example.finanzas` + SHA-1).

`build.gradle.kts` config worth knowing (already set — no manual edit needed):
- `minSdk = flutter.minSdkVersion` (Flutter ≥ 3.24 → 24; satisfies ML Kit,
  dynamic color and `google_sign_in` 7.x, all of which want 21+).
- Core library desugaring (required by `flutter_local_notifications`, or the
  release build fails at `checkReleaseAarMetadata`):
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
- Add `WRITE_EXTERNAL_STORAGE` with `android:maxSdkVersion="29"` (required by `gal` to copy receipt photos into a gallery album on Android ≤ 9; API 30+ writes via MediaStore without any permission).
- Declare the payment-notification reader `PaymentNotificationListenerService` with `android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"` and an `intent-filter` for `android.service.notification.NotificationListenerService` (`exported="true"`; the bind permission is held by the system, so no `uses-permission` is needed). The user grants access from the system "notification access" screen. See "Lectura de notificaciones de pago (fase 7)".
- Add `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` permissions and declare the `flutter_foreground_task` service (**do not rename it**) so the sync server can stay alive in the background. Include `android:stopWithTask="true"` so that swiping the app out of recents stops the service **and removes its persistent notification** (otherwise the notification is orphaned once the `HttpServer` — which lives in the main isolate — dies with the process). `stopWithTask` only fires on task removal, so the keep-alive still works for screen-off / background:
  ```xml
  <service
      android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
      android:foregroundServiceType="dataSync"
      android:stopWithTask="true"
      android:exported="false" />
  ```
- Set `android:allowBackup="false"` + `android:fullBackupContent="false"` on `<application>`. Without this, Android Auto Backup silently uploads the Isar DB — which holds the sync tokens and the Nextcloud app password used by cloud backups — to the *user's* Google Drive, unprompted. The cloud-backup feature is the deliberate, consented way to get data off the device. See "Copias de seguridad en la nube (fase 8)".

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
produced it. To ship a working desktop webapp (see "Webapp de escritorio" below), pack it
into `assets/webapp.zip` **before** building the APK — otherwise the phone serves the
"not built yet" placeholder page:

```bash
flutter build web -t lib/main_web.dart
dart run tool/pack_webapp.dart
flutter build apk --release
mkdir -p ~/Documentos/finanzas
cp build/app/outputs/flutter-apk/app-release.apk \
   ~/Documentos/finanzas/finanzas-$(git rev-parse --short HEAD).apk
```

`assets/webapp.zip` is checked in as a placeholder (a small "webapp not built" page) so
`flutter pub get`/`analyze`/`test` never break on a missing declared asset; running the
two commands above overwrites it in place with the real build — expect `git status` to
show it modified afterward, and don't commit that (same spirit as `build/`, which is
git-ignored). `.github/workflows/build-apk.yml` does **not** run the pack step, so
CI-built APKs ship the placeholder — acceptable for now, see the webapp section.

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
                     # + quickAddMain (popup) and paymentIngestMain (headless), both @pragma('vm:entry-point')
  main_web.dart      # entrypoint of the desktop webapp (no Isar; talks HTTP to the phone)
  app.dart           # MaterialApp.router + DynamicColorBuilder + AMOLED dark theme
                     # + lifecycle hooks: linked auto-sync, backup runIfDue, payment drain
  core/
    db/              # IsarService (open + schemas), migration_service.dart, isarProvider
    money/           # Money value object (see below)
    sync/            # Syncable contract (uuid/updatedAt/deletedAt) + stampForSave
    planning/        # goal_planning.dart — pure goal math shared with the webapp
    notifications/   # single flutter_local_notifications init shared by all features
    platform/        # MethodChannel bridges: payments, quick tile, secure screen
    router/          # go_router config + Routes constants
    theme/           # ColorScheme light/dark + AMOLED override
    icons/           # app icon constants
  data/
    models/          # 9 Isar @collection classes + enums.dart
    repositories/    # one repo per model + Riverpod providers; lookups.dart for id→entity maps
    report_service.dart / report_config.dart / report_pdf.dart / report_excel.dart / report_cover_cards.dart
    backup_service.dart  # JSON import/export + wipeSyncableData
    seed_service.dart    # default data on first launch
  features/
    home_shell.dart  # data-driven bottom-nav (sections chosen/ordered in settings; labelBehavior from settings)
    dashboard/       # configurable card grid; AppBar eye toggles the privacy mode
    movements/       # transaction list, filters, batch edit, recurring rules; FAB + small scan-ticket FAB
    receipts/        # OCR scan via ML Kit (on-device)
    accounts/        # account CRUD with unlimited-depth subaccounts (Account.parentId) + deposit_math.dart
    categories/      # category CRUD with unlimited-depth subcategories (Category.parentId)
    reports/         # report screen → PDF/Excel export
    payments/        # payment-notification reader (parser, ingest, rules)
    notifications/   # recurring-charge reminders (planner + service)
    backup/          # cloud backup: planner, retention, scheduler, Nextcloud/Drive providers
    sync/            # LAN sync: engine, codec, transport (net/), review UI
    web/             # desktop webapp (own Flutter web app, no Isar)
    settings/        # app settings, goals (planning), dashboard config, nav config, server/payments/backup screens
    security/        # app lock gate + device-credential auth (local_auth) + secure screen
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

**Revisión solo si hay conflicto:** `LanSyncServer._handleChangelog` auto-finaliza
la sesión en el momento (con `SyncDecisions()` por defecto, que **acepta** todas
las altas y actualizaciones limpias — ver `SyncEngine._resolveApproved`) siempre
que `plan.conflicts` esté vacío. Solo abre una `ReviewSession` pendiente (que
exige un tap del admin) cuando hay un **conflicto real** (ambos lados tocaron la
misma entidad por uuid desde el último watermark). Así los cambios que solo
existen en el admin —y las altas nuevas del vinculado— llegan con un único
"Sincronizar ahora", sin depender de que alguien confirme una sesión.

**Emparejar borrando este dispositivo (evita duplicados):** un móvil recién
instalado ya sembró sus categorías/cuentas por defecto (`SeedService`) con uuids
nuevos; al fusionar, el admin no las conoce → se añadirían en ambos lados
(duplicados). Por eso el panel del vinculado (`sync_screen.dart`) ofrece, bajo
los campos IP/puerto/PIN, un check **"Borrar datos de este dispositivo"**: al
confirmar, `BackupService.wipeSyncableData()` limpia las 6 colecciones
sincronizables + `merchantRules` (sin tocar `settings` ni `syncPeers`), empareja
y sincroniza, adoptando los datos del principal. Como defensa de raíz,
`SeedService.seedIfEmpty()` **no siembra** si ya existe un `SyncPeer`
`remoteIsAdmin==true` (este dispositivo es un vinculado que adopta del admin).

**Filtro de IP:** `localIpv4Addresses()` (`sync_identity.dart`) devuelve solo las
IPv4 del **mejor rango LAN presente** (`192.168/16` > `172.16/12` > `10/8` >
resto, descartando link-local `169.254`) vía `preferLanAddresses` (pura,
testeada). Así el emparejamiento y la dirección de la webapp muestran la IP de la
Wi-Fi buena y no la de datos móviles/VPN.

**Ajustes del servidor** (`server_settings_screen.dart`, Ajustes →
"Ajustes del servidor"): campos **locales** de `AppSettings` (no se sincronizan
ni se respaldan) — `syncPort`, `syncRequirePin` + `syncFixedPin` (PIN fijo o
aleatorio, o sin PIN), `syncKeepAliveInBackground`, `syncAutoStartServer`,
`syncLinkedAutoSyncEnabled`. `SyncServerController.start()` lee puerto/PIN al
arrancar; `restart()` los aplica en caliente. Extras: regenerar PIN, revocar
todos los vinculados (`revokeAllLinkedPeers`), registro de actividad.

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

**Servicio en primer plano (mantener el servidor vivo):** con
`syncKeepAliveInBackground` activo, `SyncServerController.start()/stop()` arranca
y para un servicio en primer plano (`sync_foreground_service.dart`, sobre
`flutter_foreground_task`) con notificación persistente. Su único fin es evitar
que Android mate el proceso: el `HttpServer` sigue en el isolate principal y el
task handler no hace trabajo. **Limitación:** con la app **cerrada del todo**
(deslizada de recientes) el servicio puede pararse según el fabricante; cubre
pantalla apagada / app en segundo plano. En iOS los servidores en segundo plano
están muy restringidos.

**Auto-sync del vinculado:** con `syncLinkedAutoSyncEnabled` (por defecto true),
`app.dart` intenta `tryBackgroundSyncAll()` al abrir/reanudar la app y, vía
`connectivity_plus`, **al conectarse a una Wi-Fi** (aproxima "ambos en la misma
red" por alcanzabilidad del admin guardado; sin descubrimiento mDNS). Con
`syncAutoStartServer`, el admin levanta el servidor solo al abrir la app.

### Webapp de escritorio (fase 4)

> **Regla: si una funcionalidad existe en móvil y en la webapp, se actualizan
> juntas.** La web ha tenido secciones que fueron a la zaga del móvil (p. ej.
> el informe: durante un tiempo el selector de tipo de movimiento de la web no
> ofrecía "Ambos" aunque el móvil sí, y las opciones no se guardaban). Cuando
> toques una feature compartida (informe, tarjetas del dashboard, ajustes que
> viajan por `/api/settings`, etc.), aplica el cambio en los dos sitios en el
> mismo commit — no lo dejes para "después". Si de verdad solo aplica a una
> plataforma, dilo explícitamente en el commit/PR para que quede claro que no
> es un olvido.

Usar la app desde el ordenador (`lib/features/web/`, entrypoint `lib/main_web.dart`).
Es una app Flutter **web aparte**: no abre Isar ni monta `FinanzasApp`; habla con
el móvil por HTTP con `WebApiClient`, reutilizando el emparejamiento por PIN del
sync para obtener el token. Está **desacoplada de Isar** (DTOs planos en
`web_models.dart`; solo reutiliza `enums.dart` y `Money`, que son Dart puro) para
poder compilar al target web.

La API de datos vive en el servidor del móvil bajo `/api/*` (`data_api.dart`,
protegida por token) y reutiliza los repositorios de la app, así que las altas y
borrados desde la web pasan por el **mismo camino de escritura** (sellado de sync,
soft-delete) que la UI del móvil.

Superficie actual de la API (toda con `Authorization: Bearer <token>`; los DTOs
se serializan en `api_serializer.dart` y se consumen con `WebApiClient`):

| Recurso | Endpoints |
| --- | --- |
| Cuentas | `GET/POST /api/accounts`, `PUT/DELETE /api/accounts/{id}` |
| Categorías | `GET/POST /api/categories`, `PUT/DELETE /api/categories/{id}` |
| Movimientos | `GET/POST /api/transactions`, `PUT/DELETE /api/transactions/{id}`, `POST /api/transactions/batch` (`setCategory` / `setAccount` / `delete`) |
| Recurrentes | `GET/POST /api/recurring`, `PUT/DELETE /api/recurring/{id}` |
| Objetivos | `GET/POST /api/goals`, `PUT/DELETE /api/goals/{id}` |
| Tickets | `GET/POST /api/receipts`, `DELETE /api/receipts/{id}`, `GET /api/receipts/{id}/image` |
| OCR | `POST /api/ocr` (la imagen la reconoce **el móvil**: ML Kit no existe en web) |
| Informes | `POST /api/report/pdf`, `POST /api/report/excel` (se generan en el móvil y el navegador descarga el binario) |
| Ajustes | `GET/PUT /api/settings` |

Al añadir un endpoint: DTO en `web_models.dart` + serialización en
`api_serializer.dart` + método en `WebApiClient` + caso en `data_api.dart`, y un
test en `web_api_test.dart` (levanta el servidor real contra una Isar temporal).

**Se sirve desde el propio móvil, no hace falta un PC aparte para usarla:**
`LanSyncServer` sirve el build estático (`_serveStatic`/`webRoot`) en cualquier ruta
que no sea `/pair`, `/api/*` ni `/sync/*` — cualquier navegador en la misma Wi-Fi que
abra `http://<ip-del-principal>:<puerto>` recibe la webapp entera; `WebConnectScreen`
autorrellena host/puerto desde `Uri.base` porque justo espera correr así. Ajustes →
apartado "Webapp de escritorio" muestra la dirección en vivo (con botón de copiar)
cuando el servidor está activo.

El build de `flutter build web` se empaqueta como **un solo fichero zip**
(`assets/webapp.zip`, asset declarado en `pubspec.yaml`) en vez de como carpeta: el
bundling de assets de Flutter **no es recursivo** (`_parseAssetsFromFolder` en
`flutter_tools` descarta subdirectorios en silencio), y un build web tiene carpetas
anidadas (`assets/`, `canvaskit/`, `icons/`) — una carpeta declarada tal cual habría
dejado la webapp a medias (sin fuentes/canvaskit) de forma silenciosa y dependiente
de la versión del SDK. `WebappAssets.ensureExtracted()`
(`lib/features/sync/net/webapp_assets.dart`) descomprime ese zip con `package:archive`
a un directorio real (`path_provider`, cacheado por tamaño de fichero) la primera vez
que arranca el servidor, y ese directorio es el `webRoot` que se le pasa a
`LanSyncServer` — nunca lanza: si el asset falta o está roto, el servidor sigue
sirviendo solo la API con normalidad.

⚠️ **Recursión del zip:** como `assets/webapp.zip` está declarado en
`pubspec.yaml`, el build web lo incluye a su vez como asset
(`build/web/assets/assets/webapp.zip`) — sin remedio, cada ciclo build+pack
anidaría el zip del ciclo anterior y el fichero crecería sin límite (llegó a
190 MB). `tool/pack_webapp.dart` borra esa copia anidada del build antes de
comprimir (la webapp nunca la lee; solo la sirve el móvil), así que el tamaño
queda estable. No quites ese paso del tool.

`assets/webapp.zip` va commiteado como **placeholder** (una página "aún no
compilada"); generar el build real y empaquetarlo:
```bash
flutter create . --platforms=web           # genera web/ (no versionado), una vez
flutter run -d chrome -t lib/main_web.dart  # iterar en lib/features/web/ desde un PC
flutter build web -t lib/main_web.dart      # build real en build/web
dart run tool/pack_webapp.dart              # lo empaqueta en assets/webapp.zip
```
Ver "Building the APK" arriba: los dos últimos comandos van antes de compilar la APK
de release para que lleve la webapp de verdad.

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
- **Álbum en la galería** (`gal`, `receipt_image_store.dart`
  `saveReceiptToGallery`): al guardar un ticket con foto nueva se copia también
  al álbum "Finanzas" de la galería del móvil, para poder verlo desde la app de
  Galería/Fotos. Es **mejor esfuerzo** (no lanza si no hay permiso ni interrumpe
  el guardado); la copia persistente de la app en `receipts/` sigue siendo la
  fuente de verdad. El detalle del ticket tiene además un botón "Guardar en
  galería" para volcar tickets antiguos al álbum bajo demanda.

### Lectura de notificaciones de pago (fase 7)

Lee las notificaciones de pago del móvil y **crea el gasto automáticamente**
(`lib/features/payments/`). Google Wallet
(`com.google.android.apps.walletnfcrel`) funciona sin configurar; además se
pueden añadir **otras apps** definiendo *dónde buscar* cada dato con regex por
campo. Todo son ajustes **locales** de este dispositivo (no se sincronizan ni se
respaldan): `AppSettings.paymentReaderEnabled`, `paymentDefaultAccountId`,
`paymentProcessedHashes`, `notificationAppRules`, `cardAccountRules`.

**Nativo (Android):** `PaymentNotificationListenerService.kt` es un
`NotificationListenerService` que, para los paquetes configurados, bufferiza
`título/texto/postedAt/paquete` en `SharedPreferences` (lista JSON, tope 200).
Vive fuera del engine de Flutter → captura pagos **aunque la app esté cerrada**.
`MainActivity` expone el canal `com.example.finanzas/payments`
(`isPermissionGranted`, `openListenerSettings`, `drainBuffer`, `peekBuffer`,
`setSourcePackages`); el puente Dart es
`lib/core/platform/payment_notifications.dart` (tolerante a
`MissingPluginException` en tests/no-Android). Los paquetes de origen se
**derivan** de las reglas (Wallet + `notificationAppRules`).

**Parser puro (`notification_parser.dart`, testeado):** `NotificationRule`
(paquete + regex opcionales `merchantRegex`/`amountRegex`/`cardRegex` +
`merchantFromTitle`) y `applyRule`/`parseWithRules` → `ParsedPayment`
(importe en céntimos, comercio, **tarjeta** `••NNNN`, fecha). Google Wallet es
una regla built-in implícita (`NotificationRule.wallet()`, tienda en el título +
heurísticas genéricas de importe/tarjeta), **no** se guarda en ajustes. Un regex
vacío o inválido degrada a la heurística; un `amountRegex` que no casa marca "no
es un pago". `known_supermarkets.dart` (Lidl/Mercadona/Dia → "Alimentación") es
solo un *fallback*.

**Ingesta (`payment_ingest_service.dart`):** `drainAndProcess()` drena el buffer,
parsea con las reglas, deduplica por huella (`importe|comercio|día`) y con
`findPossibleDuplicate`, y crea el gasto. **Categoría** (prioridad):
1) `MerchantRule` de usuario (memoria **compartida con el OCR de tickets**);
2) supermercado conocido; 3) `ReceiptParser.suggestCategory`. **Cuenta**:
1) regla `cardAccountRules` que case la tarjeta; 2) `paymentDefaultAccountId`;
3) primera cuenta activa. La tarjeta se anota en `TransactionModel.note`. Avisa
con una notificación tocable (payload `payment:<txnId>` → abre el editor del
movimiento). Se llama desde el **engine headless** (ver abajo), en `main()`
(`_setUpPayments`, sin bloquear) y al reanudar la app (`app.dart`).

**Engine headless (el gasto se crea con la app cerrada):** el listener nativo
solo bufferiza, así que sin esto el gasto no existiría hasta que alguien abriera
la app. `PaymentIngestEngine.kt` arranca, desde `onNotificationPosted`, un
`FlutterEngine` **sin UI** que ejecuta el entrypoint `paymentIngestMain`
(`main.dart`, `@pragma('vm:entry-point')`, sin `runApp`) y lo destruye cuando
Dart avisa por el canal `com.example.finanzas/payment_ingest` (`finished`), con
timeout de 60 s de red de seguridad, debounce de 1,2 s (Wallet republica la misma
notificación) y un reintento si entró algo entre el drenado y el apagado. No
arranca ningún servicio: el sistema ya tiene enlazado el listener, así que las
restricciones de background-start de Android 12+ no aplican. Cuatro cosas que no
son obvias:

- **El canal se registra en los dos engines** (`PaymentsChannel.kt`, compartido
  con `MainActivity`). Si faltara en el headless, `drainBuffer()` daría
  `MissingPluginException`, el puente Dart lo degradaría a lista vacía y no se
  procesaría nada **sin decirlo**.
- **`FlutterEngine(Context)` ya registra los plugins solo**: no hay que llamar a
  `GeneratedPluginRegistrant`. Isar no lo necesita (su plugin Android es un
  no-op); `path_provider` y `flutter_local_notifications` sí, y funcionan.
- **Pedir el permiso de notificaciones revienta sin Activity** (el plugin usa
  `mainActivity` sin comprobar null): por eso `local_notifications.dart` aísla esa
  llamada en su propio `try/catch`. Sin eso, el gasto se crearía sin avisar.
- **El listener debe seguir en el proceso principal**: nunca le pongas
  `android:process`. La ingesta abre la misma instancia de Isar que la UI, e Isar
  admite varios isolates pero **no** varios procesos (se corrompería).

**Pendientes vs. historial (dos buffers):** el nativo guarda cada captura en dos
listas. `KEY_BUFFER` son los **pendientes**, que el engine drena (y vacía) un
segundo después de cada pago. `KEY_RECENT` (tope 50) es el **historial** que lee
`peekBuffer` para el visor y el probador de reglas de los ajustes: si el probador
leyera de los pendientes saldría **siempre vacío** —el engine ya los drenó— y no
habría forma de depurar una regla. Apagar el lector limpia los dos.

**Gate tri-estado:** `paymentReaderEnabled` vive en Isar, que Kotlin no ve con la
app cerrada, así que se **espeja** a `SharedPreferences` (`KEY_ENABLED`) desde
`syncPaymentReaderToNative` (`payment_reader_sync.dart`), único sitio que calcula
los paquetes y espeja el flag — llamado en `main()` y tras cada cambio de ajustes.
Ausente = versión recién actualizada que aún no se ha abierto: bufferiza pero no
arranca el engine (comportamiento de siempre, se autocura al abrir); `false` = ni
bufferiza, y limpia el buffer (si no, se llenaría hasta 200 y al reactivar
entrarían de golpe pagos viejos).

**Ajustes** (`payment_settings_screen.dart`, Ajustes → "Automatización"): toggle,
permiso de acceso a notificaciones, cuenta por defecto, editor de **apps y
reglas** (regex por campo + botón "Probar contra capturadas" que aplica la regla
en vivo sobre `peekBuffer`), editor **tienda → categoría** (sobre `MerchantRule`,
compartido con el OCR) y **tarjeta → cuenta** (`cardAccountRules`), más
"Procesar ahora" y el visor de capturadas.

**Tutorial de reglas** (`payment_rules_help_screen.dart`, enlazado desde los
ajustes, la lista de apps y el editor): guía con anatomía de una notificación,
recetario de patrones copiables y las trampas del parser. La lógica es pura y
está testeada (`regex_help.dart`: `regexError` + `kRegexRecipes`); el editor valida
el regex en vivo con `regexError` porque el parser **degrada un patrón inválido a
la heurística en silencio** (`_compile` se traga la `FormatException`), lo que lo
hace indistinguible de dejar el campo vacío.

⚠️ **Al probar en un móvil, no uses `am force-stop`**: deja el listener sin enlazar
hasta reiniciar o re-conceder el permiso, y parece un fallo de la feature. Usa
`am kill`. Los gestores de batería agresivos de algunos fabricantes pueden causar
lo mismo; es inherente a la plataforma.

### Copias de seguridad en la nube (fase 8)

Sube automáticamente el JSON de `BackupService.exportJson()` a **Nextcloud**
(WebDAV) o **Google Drive** (REST), con frecuencia configurable, y permite
restaurar desde una copia remota (`lib/features/backup/`). Todo son ajustes
**locales** de `AppSettings` (no se sincronizan ni se respaldan — meter el estado
de las copias dentro de las propias copias no tendría sentido): `backupEnabled`,
`backupProvider`, `backupFrequency` + `backupEvery`, `backupHour/Minute`,
`backupAnchorAt`, `backupLastRunAt/AttemptAt`, `backupLastResult`,
`backupConsecutiveFailures`, `backupKeepLast`, `backupWifiOnly`,
`backupProviderConfigs` (lista de `BackupProviderConfig` serializados, uno por
proveedor). El JSON **no se cifra**: es restaurable a mano aunque la app
desaparezca (decisión explícita).

**Frecuencia = enum + "cada N", como `RecurringRule`:** `BackupFrequency
{daily, weekly, monthly}` × `backupEvery`. **Trimestral = `monthly` × 3** — una
sola representación canónica; no hay valor `quarterly` (daría dos formas de decir
lo mismo). La UI ofrece presets (`kBackupPresets`) + personalizada, y
`frequencyLabel(freq, every)` los nombra.

**Planificador anclado, no por intervalo (`backup_planner.dart`, puro):** la
serie de ocurrencias se calcula **siempre desde `backupAnchorAt`**
(`occurrenceAt`/`nextOccurrenceAfter`/`isBackupDue`), nunca encadenando desde la
copia anterior. El motivo es un bug sutil: encadenar con recorte de fin de mes
(31 ene → 28 feb) haría que el día se **adelantara para siempre** (28 feb → 28 mar
→ 28 abr). Anclado, la serie es 31 ene → 28 feb → **31 mar** → 30 abr, sin deriva.
Los saltos usan el desbordamiento de `DateTime(y, m, d+k)` (no `add(Duration)`)
para que la hora de pared aguante los cambios de horario de verano. `isBackupDue`
sin `lastRun` → `true` (la primera copia se hace al activar, para validar la
config ya).

**Disparo oportunista (sin WorkManager):** `BackupSchedulerService.runIfDue()` se
llama, sin bloquear, desde `main()`, desde `app.dart` al reanudar
(`didChangeAppLifecycleState == resumed`) y al entrar en Wi-Fi
(`_onConnectivityChanged`) — el mismo patrón que `materializeDue` /
`tryBackgroundSyncAll` / `drainAndProcess`. **Limitación asumida:** con la app
cerrada mucho tiempo no hay copia; se hace visible mostrando la antigüedad de la
última copia en Ajustes **en rojo** cuando se pasa. No se usa WorkManager a
propósito: su residuo huérfano ya causó el crash de release de `3b1bdfa`, y como
el contenido de la copia es la propia BD, si no abres la app tampoco hay casi nada
nuevo que copiar.

**Tres modos de fallo silencioso, tapados en el orquestador:**
1. **Backoff.** Un fallo persistente (contraseña cambiada) no avanza
   `backupLastRunAt`, así que `isBackupDue` seguiría `true` y reintentaría
   —export completo + subida— en **cada** reanudación. `backupLastAttemptAt` +
   `backupConsecutiveFailures` frenan el reintento `min(2^fallos, 24) h`.
2. **Rotación con voz.** La rotación vive en el orquestador (`list()` →
   `entriesToDelete` → `delete()`), no en los proveedores. Si falla, la copia
   sigue siendo válida pero el aviso viaja en `backupLastResult`; **nunca un
   `catch (_)` mudo**.
3. **Restaurar no borra los ajustes locales.** `BackupService.importJson` **muta
   la fila de `settings` existente** (`_applySettingsFromMap`, solo las claves de
   `_settingsToMap`) en vez de construir un `AppSettings()` nuevo. Antes, importar
   reseteaba `syncDeviceId` (¡la identidad frente a los peers!), el lector de
   pagos, las credenciales de backup… — y restaurar desde la nube llegaba a apagar
   las propias copias. Test de regresión en `backup_roundtrip_test.dart`.

**Retención (`backup_retention.dart`, puro):** nombre `finanzas_backup_<ISO-UTC>Z`
en **UTC** para que el orden lexicográfico == cronológico siempre (con hora local,
el horario de verano rompería el orden y la rotación borraría la copia
equivocada). `entriesToDelete` **ignora ficheros ajenos** (`isBackupFilename`). El
"conservar N copias" se traduce a historial real con `retentionHorizonLabel`
("≈ 10 días") porque 10 copias diarias son solo 10 días.

**Id de notificación de fallo: `800000000`** (rango libre; pagos `810000000+`,
sync `900000000+`). Solo avisa a partir del 2.º fallo consecutivo. Payload
`backup` → abre `Routes.backup` (enrutado en `app.dart`).

**Proveedores (`http` plano, sin `googleapis`):** ambos con cliente inyectable
para tests contra un `HttpServer` local (como `lan_sync_test.dart`).
- Nextcloud (`nextcloud_provider.dart`): Basic auth con **contraseña de
  aplicación**, `remote.php/dav/files/<user>/<carpeta>`. MKCOL idempotente
  (**405 = ya existe, no es error**). Credenciales en Isar en claro, como
  `SyncPeer.token` (NO `flutter_secure_storage`: su `read()==null` al invalidarse
  el Keystore es indistinguible de "no configurado", justo el fallo silencioso que
  este repo evita).
- Google Drive (`google_drive_provider.dart` + `google_drive_auth.dart`): única
  dependencia nueva **`google_sign_in: ^7.2.0`**, solo para el token. En la v7
  `authenticate()` ya **no** da token: se pide aparte con
  `authorizationClient.authorizationForScopes` (silencioso) /
  `authorizeScopes`/`authorizationHeaders` (interactivo). Scope **solo
  `drive.file`** (no sensible → sin verificación de seguridad de Google; ve solo
  los ficheros que crea la app). El `folderId` se cachea en la config.
  **Limitación de `drive.file`:** la restauración no lista copias que la app no
  haya creado (subidas a mano, o tras revocar el acceso) — la UI lo avisa y queda
  "Importar datos" desde fichero como escape.

**OAuth de Google (una vez, en Google Cloud Console):** habilitar Drive API →
pantalla de consentimiento **Externo** y **PUBLICAR** (en *Testing* el refresh
token caduca a los 7 días) → credencial **OAuth tipo Android** con paquete
`com.example.finanzas` y el **SHA-1 de release *y* de debug** (o Drive falla solo
en un tipo de build). Solo `drive.file`. No hace falta `google-services.json` ni
client secret. Las APK de CI van con clave de debug de CI → otro SHA-1 → Drive no
funciona ahí (Nextcloud sí).

### Cuentas: depósitos a plazo y Letras del Tesoro

`AccountType` es `{bank, cash, investment, deposit, treasuryBill}`. Los dos
últimos son productos con **rendimiento estimado**, no movimientos reales: la
app no crea transacciones por los intereses, los **calcula** y los suma al saldo
del banco donde está el producto.

- **Depósito** (`deposit`): `depositRateBps` (TAE en **puntos básicos**, 3,75 % =
  375 — entero, nunca `double`), `depositStartDate`/`depositEndDate`,
  `depositPayout` (`atMaturity|monthly|quarterly|yearly`) y `depositAutoRenew`.
- **Letra del Tesoro** (`treasuryBill`): va **a descuento**, así que reutiliza
  `initialBalanceCents` como precio de compra, `depositStartDate` como fecha de
  compra y `depositEndDate` como vencimiento; `nominalCents` es lo que se cobra
  al final. Ganancia bruta = `nominalCents - initialBalanceCents`.
- **Matemática pura** (`features/accounts/deposit_math.dart`, testeada en
  `deposit_math_test.dart`): interés **simple** `capital · bps/10000 · días/365`.
  El redondeo al céntimo se hace **una sola vez, al final**: el neto se calcula
  sobre el bruto *sin redondear* (`depositIrpfRateBps = 1900`, el 19 % de
  retención del primer tramo) para no encadenar dos redondeos. Es una
  **estimación orientativa**, no una liquidación fiscal.
- **Banco asociado** (`bankAccountId` → `holdingBankId`): se elige libremente,
  también en subcuentas (no tiene por qué ser el `parentId`); si no se elige y es
  subcuenta, recae en el padre. `AccountRepository.balanceCents` recorre los
  depósitos/letras cuyo `holdingBankId` sea esa cuenta y les suma el rendimiento
  estimado.

### Objetivos (planificación de ahorro)

`Goal` + `core/planning/goal_planning.dart` (**puro**, sin Isar, para que el
`GoalDto` de la webapp comparta exactamente la misma matemática; testeado en
`goal_planning_test.dart`). Dos modos en `planMode`:
`'contribution'` (aporto `monthlyContributionCents` al mes → `monthsToTarget` /
`projectedDate`) y `'deadline'` (fijo `deadline` → `requiredMonthlyCents`). Los
getters del modelo son `@ignore` y delegan en las funciones puras. Los objetivos
son un módulo opcional del dashboard/nav (`AppModule.goals`).

### Informes (PDF y Excel)

`report_service.dart` calcula `ReportData` (evolución por semana/mes/año,
rankings por categoría/cuenta/concepto, uso de cuentas, medias, récords y
comparativa con el periodo anterior equivalente) y `report_pdf.dart` /
`report_excel.dart` lo renderizan. La pantalla es `features/reports/`; la webapp
llama a `POST /api/report/pdf|excel`, o sea que **el informe se genera siempre en
el móvil** y el navegador solo descarga el fichero.

- **`report_config.dart` está separado de `report_service.dart` a propósito**:
  `ReportConfig` (flujo, orden, granularidad, tarjetas de portada) es Dart puro y
  lo importa la webapp; `report_service.dart` importa Isar. Los `*.g.dart` de Isar
  llevan ids `int64` como literales que **`dart2js` no puede representar**, así
  que cualquier import transitivo de Isar rompe `flutter build web`. Si añades
  opciones al informe, van en `report_config.dart`.
- **Portada personalizable**: `kReportCoverCatalog` (`report_cover_cards.dart`)
  es el catálogo de tarjetas (kpi / chart / block) y `kDefaultReportCoverCards`
  (en `report_config.dart`, sin dependencia de Material) el valor por defecto —
  un único origen de verdad para editor y decodificador. **Excel ignora las
  `chart`** (XlsIO no dibuja gráficos aquí). La configuración se persiste
  serializada en `AppSettings.reportConfig`.
- El PDF empaqueta **Noto Sans** (`assets/fonts/`) porque las fuentes por defecto
  de `package:pdf` no traen el glifo `€`.
- Cuidado con la portada vacía: si las tarjetas elegidas no aplican al flujo o no
  hay datos, hay que degradar con gracia (fue el bug de `f398cb5`).
- **Dos trampas de render de `package:pdf` que dejaron páginas en blanco sin
  ningún error** (ambas con test de regresión en `report_generation_test.dart`):
  1. **Nada de `CrossAxisAlignment.stretch` en filas dentro de la `Column` de la
     portada**: los hijos de esa `Column` se miden con altura sin acotar, y con
     stretch el paquete impone a las celdas `minHeight = maxHeight = ∞` — la
     rejilla de KPIs y todo lo posterior dejaba de pintarse (portada solo con el
     banner). La portada se construye en `buildCoverWidgets` (expuesta
     `@visibleForTesting` justo para poder afirmar que sus cajas de layout son
     finitas tras `save()`).
  2. **`FixedAxis` con un solo valor divide por cero** (rango 0..0 → NaN): un
     informe de un solo periodo (p. ej. "Este mes" con granularidad mensual)
     reventaba la aserción de `PdfNum` en debug y en release escribía `NaN` en el
     flujo de contenido — el visor mostraba esa página en blanco. `_barBlock`
     centra el único periodo entre dos etiquetas vacías para dar anchura al eje.

### Bloqueo y privacidad de pantalla

`features/security/`: `AppLockGate` envuelve la app y exige autenticación
(`local_auth`, `biometricOnly: false` → vale la huella **o** el PIN/patrón del
teléfono; la app no guarda ninguna credencial) cuando `AppSettings.appLockEnabled`.
`privacy_screen_gate.dart` + `core/platform/secure_screen.dart` aplican
`FLAG_SECURE` para ocultar el contenido en el conmutador de tareas
(`secureScreenEnabled` es `bool?` **a propósito**: `null` = nunca configurado, se
distingue de un `false` explícito). El popup de alta rápida **no** pasa por el
gate (es un entrypoint aparte).

### Dashboard y navegación configurables

Ambas cosas son listas de nombres de enum en `AppSettings`, resueltas con
`enumByName` y con getters que filtran lo desconocido:
`dashboardCards`/`webDashboardCards` (`DashboardCardType`) y `navSections`
(`NavSection`), más `totalBalanceAccountIds`, `accountsCardIds` y
`balanceSubtotals` para acotar qué cuentas entran en cada tarjeta. `home_shell.dart`
construye la barra inferior desde esos datos (`alwaysShowNavLabels` decide el
`labelBehavior`). Al añadir un valor nuevo al enum, **añádelo también al orden por
defecto** y comprueba que un ajuste guardado con el valor viejo sigue decodificando.

### Privacy mode (hide amounts)

`AppSettings.hideAmounts` (toggled by the eye in the dashboard AppBar) masks every monetary value app-wide. Render amounts with `MoneyText` (`lib/shared/widgets/money_text.dart`), which watches `hideAmountsProvider` and shows `kHiddenAmount` when active — prefer it over `Text(Money(x).format())` for on-screen figures.

### State / data flow

Isar is opened once in `main()` and injected via `isarProvider.overrideWithValue(isar)`. Every repository receives `Isar` through its Riverpod provider watching `isarProvider`. Screens watch `FutureProvider`s (or `StreamProvider` wrappers around `watchLazy`) for reactive updates.

### Data migrations (Isar) — el centinela `Int.MIN`

`IsarService.open()` llama a `runMigrations(isar)` (`core/db/migration_service.dart`)
justo tras abrir la BD y antes de que ningún repositorio lea. El guard es
`AppSettings.dataVersion` **dentro del `writeTxn`**, así que es idempotente y
seguro con el acceso multi-isolate del quick-add.

⚠️ **Al añadir un campo `int` (o `bool`/`DateTime`) no-nullable a una colección
que ya tiene filas, Isar rellena esas filas con su centinela
`-9223372036854775808` (Int.MIN), NO con el valor por defecto del constructor
Dart.** Ya pasó: la UI llegó a mostrar "conservar las últimas
-9223372036854775808 copias" (v2 de las migraciones, `_sanitizeBackupFields`).
Cada vez que añadas un campo así:
1. sube `kCurrentDataVersion` y escribe el saneo (solo tocando lo que esté fuera
   de rango, para no pisar lo que el usuario sí configuró), y
2. si el campo tiene que distinguir "sin configurar" de un valor real, hazlo
   **nullable** (como `secureScreenEnabled`).

Historial: **v1** backfill de `uuid`/`updatedAt` en las colecciones sincronizables;
**v2** saneo de los `int` de las copias en la nube.

### Tests

~40 ficheros en `test/`, casi todos sobre **lógica pura** (money, planificadores,
parsers, retención, regex, codec de sync) más unos cuantos de integración con Isar
real y con un `HttpServer` local (`lan_sync_test.dart`, `web_api_test.dart`,
`nextcloud_provider_test.dart`, `google_drive_provider_test.dart`). Los que
necesitan la BD usan `test/support/test_isar.dart`, que descarga el binario nativo
(`Isar.initializeIsarCore(download: true)`, hace falta red la primera vez) y abre
una instancia temporal con nombre único — ciérrala siempre con
`isar.close(deleteFromDisk: true)`.

Regla práctica: cuando una feature tenga decisiones no triviales (fechas, dinero,
parseo, orden), **extrae la lógica a una función pura** en su propio fichero y
testéala ahí; es el patrón que sigue todo el repo (`backup_planner.dart`,
`notification_planner.dart`, `deposit_math.dart`, `sync_qr.dart`, `regex_help.dart`…).

### Money handling

All monetary amounts are stored and computed as **integer cents** (`amountCents`, `totalCents`, `buyPriceCents`, …). `Money` (`lib/core/money/money.dart`) is the value object for parsing user input (`Money.parseToCents`) and formatting output (`money.format()`). Never use `double` for money arithmetic.

Investment share quantities use `quantityScaled` (×10⁶ integer) to represent fractional shares without precision loss.

### Isar enums

All enums are persisted **by name** (`@Enumerated(EnumType.name)`). When adding or reordering enum values, never rely on index order. Use `enumByName()` from `lib/data/models/enums.dart` for safe parsing with a fallback instead of `.byName()` (which throws).

### Navigation

Routes are defined as constants in `Routes` (`lib/core/router/app_router.dart`). Extra data is passed via `context.go(Routes.xxx, extra: value)` and retrieved with `state.extra`. Use `_intExtra()` helper for optional int IDs.

## CI

`.github/workflows/build-apk.yml` runs on `workflow_dispatch` or pushes to `v*` tags:
it regenerates `*.g.dart` with `build_runner` and builds a release APK, uploaded as an
artifact (and attached to a GitHub Release on `v*` tags).

To publish a release:
```bash
git tag v0.x.y && git push origin v0.x.y
```

**Tres cosas que hacen que la APK de CI NO sea distribuible** (a propósito, pero
conviene tenerlas presentes):
1. Va firmada con la **clave de depuración** del runner (no hay keystore en
   secrets) → no puede actualizar una instalación firmada con `finanzas.keystore`,
   y su SHA-1 no es el registrado en el cliente OAuth → **Google Drive no funciona**
   ahí (Nextcloud sí).
2. **No** ejecuta `dart run tool/pack_webapp.dart`, así que lleva el
   `assets/webapp.zip` placeholder: el móvil serviría la página de "aún no
   compilada" en vez de la webapp.
3. ⚠️ **Deuda técnica:** el workflow sigue ejecutando
   `flutter create . --org com.hectorruz --platforms=android` y parcheando el
   manifest con `sed`, herencia de cuando `android/` no estaba versionado. Hoy
   `android/` **sí lo está**, así que ese paso pisa el manifest y el Gradle
   commiteados y cambia el `applicationId` a `com.hectorruz.finanzas`. Habría que
   borrar esos dos pasos (checkout → pub get → build_runner → build). Ver AGENTS.md.
