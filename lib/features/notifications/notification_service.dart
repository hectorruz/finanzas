import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/db/isar_provider.dart';
import '../../core/notifications/local_notifications.dart';
import '../../data/models/recurring_rule.dart';
import 'notification_planner.dart';

/// Programa las notificaciones locales de las reglas recurrentes.
///
/// Los avisos son **pasivos** (solo informan); el cargo se materializa siempre
/// vía `materializeDue`. Se reprograma todo al arrancar la app y al guardar o
/// borrar una regla — como los ids de notificación son los ids de regla,
/// reprogramar sustituye lo anterior sin duplicados.
class RecurringNotificationService {
  RecurringNotificationService(this._isar);

  final Isar _isar;

  static const _channel = AndroidNotificationDetails(
    'recurring',
    'Cargos recurrentes',
    channelDescription: 'Avisos de próximos cargos e ingresos recurrentes',
    importance: Importance.defaultImportance,
  );

  /// Cancela y vuelve a programar el próximo aviso de cada regla habilitada.
  ///
  /// Cancela **solo** los ids de regla (nunca `cancelAll()`): el recordatorio
  /// de sincronización (`SyncReminderService`) usa el mismo plugin/canal
  /// nativo con sus propios ids y no debe perder su programación cada vez que
  /// esto se reprograma.
  Future<void> rescheduleAll() async {
    if (!await ensureNotificationsInitialized()) return;
    final allRules = await _isar.recurringRules.where().findAll();
    for (final r in allRules) {
      await localNotificationsPlugin.cancel(id: r.id);
    }

    final rules = await _isar.recurringRules
        .filter()
        .deletedAtIsNull()
        .activeEqualTo(true)
        .notifyEnabledEqualTo(true)
        .findAll();
    for (final plan in planNotifications(rules)) {
      await localNotificationsPlugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        scheduledDate: tz.TZDateTime.from(plan.when, tz.local),
        notificationDetails: const NotificationDetails(android: _channel),
        // Inexacta: para un aviso informativo no hace falta alarma exacta y así
        // no exigimos el permiso SCHEDULE_EXACT_ALARM (restringido en A14+).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

final recurringNotificationServiceProvider =
    Provider<RecurringNotificationService>(
  (ref) => RecurringNotificationService(ref.watch(isarProvider)),
);
