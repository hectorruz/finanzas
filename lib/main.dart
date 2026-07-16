import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:isar_community/isar.dart';

import 'app.dart';
import 'core/db/isar_provider.dart';
import 'core/db/isar_service.dart';
import 'data/repositories/recurring_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/seed_service.dart';
import 'features/notifications/notification_service.dart';
import 'features/payments/payment_ingest_service.dart';
import 'features/payments/payment_reader_sync.dart';
import 'features/quick_add/quick_add_popup.dart';
import 'features/sync/sync_reminder_service.dart';

/// Entrypoint del popup de alta rápida lanzado por el tile de Ajustes rápidos
/// (Android `QuickAddActivity`). Abre solo un diálogo translúcido para añadir
/// un ingreso/gasto, sin montar la app completa ni el bloqueo.
@pragma('vm:entry-point')
Future<void> quickAddMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES', null);
  final isar = await IsarService.open();
  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const QuickAddPopupApp(),
    ),
  );
}

/// Entrypoint **sin interfaz** que ejecuta el engine headless que arranca
/// `PaymentIngestEngine` (Kotlin) cuando llega una notificación de pago: abre
/// Isar, drena el buffer nativo y crea los gastos. Es lo que hace que el gasto
/// aparezca sin abrir la app.
///
/// No llama a `runApp`: no hay ventana, solo el binding para que funcionen los
/// canales de plataforma. Isar no se cierra al terminar — la instancia nativa es
/// única por proceso y puede estar compartida con el engine de la interfaz.
@pragma('vm:entry-point')
Future<void> paymentIngestMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  var created = 0;
  try {
    final isar = await IsarService.open();
    created = await PaymentIngestService(isar).drainAndProcess();
  } catch (e, st) {
    debugPrint('paymentIngestMain: $e\n$st');
  } finally {
    // Avisar siempre, también tras un error: es lo que destruye el engine. Si no
    // llega, Kotlin lo mata igual por timeout, pero tardando 60 s de más.
    await _ingestLifecycle.invokeMethod<void>('finished', created);
  }
}

const _ingestLifecycle = MethodChannel('com.example.finanzas/payment_ingest');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge explícito: en Android con Flutter ≥3.24 y compileSdk alto el
  // modo edge-to-edge es obligatorio (la app dibuja bajo las barras del
  // sistema). Lo fijamos de forma determinista y dejamos la barra de navegación
  // transparente; cada pantalla/hoja añade el padding del inset inferior para
  // que los botones no queden tapados por la barra de 3 botones.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  // Datos de localización para DateFormat en español.
  await initializeDateFormatting('es_ES', null);

  // Inicialización asíncrona de Isar ANTES de runApp (directiva de calidad #4):
  // así inyectamos la instancia real en el grafo de Riverpod mediante overrides
  // y evitamos cualquier `late Isar` global.
  final isar = await IsarService.open();

  // Datos por defecto la primera vez y materialización de recurrentes pendientes.
  await SeedService(isar).seedIfEmpty();
  await RecurringRepository(isar).materializeDue();

  // Reprogramar avisos (recurrentes + recordatorio de sync) sin bloquear el
  // arranque. Ambos comparten el plugin de notificaciones (ver
  // `local_notifications.dart`); la primera llamada síncrona a
  // `ensureNotificationsInitialized()` gana y la otra espera el mismo future,
  // así que no hay doble inicialización aunque ninguna de las dos se espere.
  unawaited(RecurringNotificationService(isar).rescheduleAll());
  unawaited(SyncReminderService(SettingsRepository(isar)).reschedule());

  // Lectura de notificaciones de pago: sincroniza al servicio nativo las apps
  // de origen y procesa lo capturado con la app cerrada. Sin bloquear.
  unawaited(_setUpPayments(isar));

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const FinanzasApp(),
    ),
  );
}

/// Pone al día el servicio nativo (lector activo + apps de origen) y procesa lo
/// que quedara capturado. Con el engine de ingesta headless lo normal es que ya
/// esté todo procesado, pero esto cubre el hueco de la primera apertura tras
/// actualizar (cuando el nativo aún no sabía si el lector estaba activo) y el de
/// un móvil que matara el proceso antes de tiempo. Tolerante a plataformas sin
/// el canal (no-Android/tests).
Future<void> _setUpPayments(Isar isar) async {
  try {
    await syncPaymentReaderToNative(SettingsRepository(isar));
    await PaymentIngestService(isar).drainAndProcess();
  } catch (_) {
    // Plataforma sin el canal o error de arranque: se ignora.
  }
}
