import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/isar_provider.dart';
import 'core/db/isar_service.dart';
import 'data/repositories/recurring_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/seed_service.dart';
import 'features/notifications/notification_service.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const FinanzasApp(),
    ),
  );
}
