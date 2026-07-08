import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/notifications/local_notifications.dart';
import '../../data/repositories/settings_repository.dart';
import 'sync_reminder_planner.dart';

/// Programa el recordatorio local para revisar la sincronización (solo tiene
/// sentido en el admin, que es quien revisa). Es un aviso **pasivo**: solo
/// recuerda abrir la app y revisar; no sincroniza nada por sí mismo. Al tocarlo
/// se navega a la pantalla de sync (ver `payload` + `app.dart`).
class SyncReminderService {
  SyncReminderService(this._settings);
  final SettingsRepository _settings;

  /// Un id por día de la semana, en un rango que no puede chocar con los ids
  /// de regla recurrente (autoincrement de Isar, siempre mucho menores).
  static const _idBase = 900000000;

  static const _channel = AndroidNotificationDetails(
    'sync_reminder',
    'Recordatorio de sincronización',
    channelDescription:
        'Aviso para revisar los cambios de los dispositivos vinculados',
    importance: Importance.defaultImportance,
  );

  /// Cancela el recordatorio anterior y, si sigue activo, reprograma el
  /// próximo aviso de cada día configurado. Recurrente: cada aviso se vuelve a
  /// programar solo automáticamente (`matchDateTimeComponents`), sin que la
  /// app necesite reprogramar cada semana.
  Future<void> reschedule() async {
    if (!await ensureNotificationsInitialized()) return;

    for (final day in allWeekdays) {
      await localNotificationsPlugin.cancel(id: _idBase + day);
    }

    final settings = await _settings.getOrCreate();
    if (!settings.syncReminderEnabled) return;

    for (final day in resolveReminderWeekdays(settings.syncReminderWeekdays)) {
      final when = nextReminderOccurrence(
        weekday: day,
        hour: settings.syncReminderHour,
        minute: settings.syncReminderMinute,
      );
      await localNotificationsPlugin.zonedSchedule(
        id: _idBase + day,
        title: 'Sincronización pendiente',
        body: 'Toca para revisar los cambios de tus dispositivos vinculados.',
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(android: _channel),
        // Inexacta: aviso informativo, no exige SCHEDULE_EXACT_ALARM (A14+).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'sync',
      );
    }
  }
}

final syncReminderServiceProvider = Provider<SyncReminderService>(
  (ref) => SyncReminderService(ref.watch(settingsRepositoryProvider)),
);
