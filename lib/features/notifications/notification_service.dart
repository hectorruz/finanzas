import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:isar_community/isar.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/db/isar_provider.dart';
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
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'recurring',
    'Cargos recurrentes',
    channelDescription: 'Avisos de próximos cargos e ingresos recurrentes',
    importance: Importance.defaultImportance,
  );

  /// Inicializa el plugin y la zona horaria. Tolerante a fallos: si la
  /// plataforma no soporta notificaciones (p. ej. tests), queda desactivado.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name.identifier));
      } catch (_) {
        // Nos quedamos con la zona por defecto de `tz.local`.
      }
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
      );
      final ok = await _plugin.initialize(settings: initSettings);
      if (ok == false) return false;
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cancela y vuelve a programar el próximo aviso de cada regla habilitada.
  Future<void> rescheduleAll() async {
    if (!await init()) return;
    final rules = await _isar.recurringRules
        .filter()
        .deletedAtIsNull()
        .activeEqualTo(true)
        .notifyEnabledEqualTo(true)
        .findAll();

    await _plugin.cancelAll();
    for (final plan in planNotifications(rules)) {
      await _plugin.zonedSchedule(
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
