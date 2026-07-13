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
- Add `WRITE_EXTERNAL_STORAGE` with `android:maxSdkVersion="29"` (required by `gal` to copy receipt photos into a gallery album on Android ≤ 9; API 30+ writes via MediaStore without any permission).
- Add `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` permissions and declare the `flutter_foreground_task` service (**do not rename it**) so the sync server can stay alive in the background. Include `android:stopWithTask="true"` so that swiping the app out of recents stops the service **and removes its persistent notification** (otherwise the notification is orphaned once the `HttpServer` — which lives in the main isolate — dies with the process). `stopWithTask` only fires on task removal, so the keep-alive still works for screen-off / background:
  ```xml
  <service
      android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
      android:foregroundServiceType="dataSync"
      android:stopWithTask="true"
      android:exported="false" />
  ```
- Declare the Wallet notification listener (`WalletNotificationListenerService`, package `com.example.finanzas`) so the app can read Google Wallet payment notifications. No `<uses-permission>` is needed — `BIND_NOTIFICATION_LISTENER_SERVICE` is held by the system, not the app; the user grants access from *Settings → Notification access*. Same shape as the existing `QuickAddTileService` (`exported="true"` + the BIND permission):
  ```xml
  <service
      android:name=".WalletNotificationListenerService"
      android:exported="true"
      android:label="Finanzas · Wallet"
      android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
      <intent-filter>
          <action android:name="android.service.notification.NotificationListenerService" />
      </intent-filter>
  </service>
  ```

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

### Copias de seguridad automáticas (fase 7)

Copias programadas del JSON completo (`BackupService.exportJson()`, el mismo que
"Exportar datos") a **Archivo local**, **Nextcloud** o **Google Drive**, con
frecuencia **diaria / semanal / mensual** (`lib/features/backup/`). Toda la
configuración son campos **locales** de `AppSettings` (`backupEnabled`,
`backupFrequency`, `backupDestination`, `backupHour/Minute`, `backupKeepLast`,
`backupLastRunAt/Result`, `nextcloud*`, `googleDriveAccountEmail`): **no** se
sincronizan ni se incluyen en el backup exportable (no se tocó `_settingsToMap`).

- **Planificador puro** (`backup_planner.dart`, testeado inyectando `now:`):
  `isBackupDue` (diaria=1d, semanal=7d, mensual=30d desde `backupLastRunAt`) y
  `nextBackupTime` (solo informativo, para la UI).
- **Destinos** (`BackupTarget`, `upload(filename, bytes)` + `label`):
  - `LocalFileBackupTarget`: `getApplicationDocumentsDirectory()/backups/`, rota
    conservando `backupKeepLast`.
  - `NextcloudBackupTarget`: WebDAV `PUT` con `Basic` auth (app password), `MKCOL`
    de la carpeta, rotación best-effort vía `PROPFIND` + `DELETE`. Sin TLS propio
    (se apoya en el `https://` del servidor). "Probar conexión" sube y borra un
    fichero de prueba.
  - `GoogleDriveBackupTarget` + `GoogleDriveAuth`: scope **`drive.file`** (solo lo
    creado por la app). Usa **solo el flujo de autorización** de `google_sign_in`
    7.x (`authorizationClient.authorizeScopes` interactivo desde la UI;
    `authorizationForScopes` silencioso en el worker), **no** la autenticación con
    Credential Manager → basta una credencial OAuth de tipo **Android** (paquete +
    SHA-1) y **no** hace falta client id de tipo Web, `serverClientId` ni
    `google-services.json`. `AuthClient` (extensión
    `extension_google_sign_in_as_googleapis_auth`) implementa `http.Client` y se
    pasa a `drive.DriveApi`.
- **`BackupSchedulerService(Isar)`**: `runNow({notify})` (serializa → `upload` →
  actualiza estado → notifica) y `runIfDue()` (solo si toca; red de seguridad al
  abrir/reanudar la app). `_targetFor(AppSettings)` elige el destino. Canal de
  notificación `backup`, id **`800000000`** (base propia, disjunta de recurrentes
  y del sync `900000000+`).
- **Segundo plano real: WorkManager** (`backup_worker.dart`, dep
  `workmanager: ^0.9.0+3` — la 0.5.x usa APIs del *embedding v1* y **no compila**
  con Flutter 3.44). Tarea periódica (latido de 6 h; mínimo del sistema 15 min)
  con `@pragma('vm:entry-point') backupCallbackDispatcher()` que abre Isar y llama
  `runIfDue()`. Se registra/cancela en `main()` y al guardar los ajustes según
  `backupEnabled`; `requiresNetwork` si el destino no es local. Sujeto a Doze /
  límites del fabricante → la copia al abrir/reanudar (`main.dart`, `app.dart`) es
  la red de seguridad. El plugin `workmanager` **no requiere** cambios de
  manifiesto (`google_sign_in` 7.x tampoco; trae sus deps y exige `minSdk 24`, que
  ya es el default de Flutter).
- **UI**: Ajustes → "Copias de seguridad automáticas"
  (`backup_settings_screen.dart`): activar, frecuencia, hora, destino, campos de
  Nextcloud + "Probar conexión", "Conectar cuenta de Google" (con los pasos de
  Google Cloud), "Hacer copia ahora" y estado de la última copia.

**Config única de Google Cloud (la hace el usuario):** proyecto en Cloud Console
→ activar **Google Drive API** → pantalla de consentimiento OAuth (Externo, con el
usuario de prueba) → credencial **OAuth de tipo Android** con paquete
`com.example.finanzas` y la **huella SHA-1** del keystore de release
(`finanzas.keystore`). Sin esto, `authorizeScopes` falla con un error de
configuración del cliente.

### Lectura de notificaciones de Google Wallet (fase 8)

Al pagar con el móvil, lee la notificación de Google Wallet y **crea el gasto
automáticamente** (`lib/features/wallet/`). Ajustes locales de `AppSettings`
(no se sincronizan ni se respaldan): `walletReaderEnabled`,
`walletDefaultAccountId` (0 = primera cuenta activa), `walletSourcePackages`
(por defecto `com.google.android.apps.walletnfcrel`) y `walletProcessedHashes`
(huellas idempotentes, podadas a 300).

- **Servicio nativo** (Kotlin, `com.example.finanzas`)
  `WalletNotificationListenerService` extends `NotificationListenerService`:
  filtra por paquete de origen y guarda título+texto+timestamp+paquete en un
  buffer **persistente** (`SharedPreferences` `wallet_reader`, lista JSON, cap
  200). Vive independiente del engine de Flutter → **captura pagos con la app
  cerrada**. Manifiesto: ver la entrada de setup arriba.
- **Puente** MethodChannel `com.example.finanzas/wallet` (en `MainActivity.kt`,
  junto al de `quick_tile`): `isPermissionGranted`, `openListenerSettings`
  (deep-link a *Notification access*), `drainBuffer` (devuelve y vacía),
  `peekBuffer` (sin vaciar, para el visor) y `setSourcePackages`. Dart:
  `lib/core/platform/wallet_notifications.dart` (tolerante a
  `MissingPluginException` en tests/no-Android).
- **Parser puro** `wallet_notification_parser.dart` (+ test):
  `parseWalletNotification(...)` → `{cents, merchant, date}` o `null` si no es un
  pago. Heurísticas de importe (€/$, coma o punto decimal, miles) y de comercio
  ("en/at COMERCIO" o el título si no es genérico), ES + EN. **Heurístico**: el
  visor de capturas (Ajustes) sirve para afinarlo con notificaciones reales.
- **Resolución de categoría** (`wallet_ingest_service.dart`, en orden): 1)
  **supermercado conocido** (`known_supermarkets.dart`, puro/testeado — Lidl /
  Mercadona / Dia → categoría **"Alimentación"** y concepto = nombre canónico de
  la tienda; match por **palabra**, no substring, para no confundir "dia"); 2)
  `MerchantRuleRepository.categoryFor`; 3) `ReceiptParser.suggestCategory`. Si no
  hay categoría, el gasto se crea igual sin ella.
- **Creación del gasto**: `findPossibleDuplicate` (reutiliza el detector de
  tickets) contra los movimientos de ±1 día; si no es duplicado, crea el
  `TransactionModel` (gasto, cuenta por defecto) vía `TransactionRepository.save`
  (sella el sync solo) y, si la categoría es fiable, `MerchantRule.remember`.
  Notificación tocable "Gasto detectado" (canal `wallet`, id base `810000000` +
  `txnId % 1000000`) con payload `wallet:<id>` que abre el editor del movimiento
  (rama en `_handleNotificationPayload` de `app.dart`) para editar/deshacer.
- **Drenado**: `WalletIngestService.drainAndProcess()` en `main()` (arranque) y en
  el `resumed` de `app.dart`. **No** se drena desde el worker de WorkManager: su
  isolate de segundo plano no tiene registrado el MethodChannel de
  `MainActivity` (viven en engines distintos), así que los pagos capturados con
  la app cerrada se procesan en el siguiente arranque/reanudación (el buffer
  nativo persiste). Idempotente por huella `importe|comercio|día`.
- **UI**: Ajustes → "Automatización" → "Leer notificaciones de Google Wallet"
  (`wallet_settings_screen.dart`): activar, estado del permiso + botón para
  concederlo, cuenta por defecto, apps de origen (añadir/quitar), "Procesar
  ahora" y visor de notificaciones capturadas (con lo que extrae el parser).

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
