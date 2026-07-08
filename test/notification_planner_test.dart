import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/models/recurring_rule.dart';
import 'package:finanzas/features/notifications/notification_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lógica pura de planificación de avisos de recurrentes (sin plugin).
void main() {
  RecurringRule rule({
    required DateTime nextDate,
    int daysBefore = 0,
    int hour = 9,
    int minute = 0,
    bool enabled = true,
    bool active = true,
    DateTime? endDate,
    RecurringFrequency frequency = RecurringFrequency.monthly,
  }) =>
      RecurringRule()
        ..id = 1
        ..name = 'Netflix'
        ..concept = 'Netflix'
        ..amountCents = 1299
        ..frequency = frequency
        ..nextDate = nextDate
        ..endDate = endDate
        ..active = active
        ..notifyEnabled = enabled
        ..notifyDaysBefore = daysBefore
        ..notifyHour = hour
        ..notifyMinute = minute;

  group('computeNotifyTime', () {
    test('mismo día a la hora configurada', () {
      final r = rule(nextDate: DateTime(2026, 7, 15), hour: 10, minute: 30);
      expect(computeNotifyTime(r, DateTime(2026, 7, 15)),
          DateTime(2026, 7, 15, 10, 30));
    });

    test('N días antes', () {
      final r = rule(nextDate: DateTime(2026, 7, 15), daysBefore: 3, hour: 8);
      expect(computeNotifyTime(r, DateTime(2026, 7, 15)),
          DateTime(2026, 7, 12, 8, 0));
    });
  });

  group('planNotifications', () {
    final now = DateTime(2026, 7, 8, 12); // mediodía

    test('planifica el aviso futuro de la próxima ocurrencia', () {
      final plans =
          planNotifications([rule(nextDate: DateTime(2026, 7, 15))], now: now);
      expect(plans, hasLength(1));
      expect(plans.single.when, DateTime(2026, 7, 15, 9, 0));
      expect(plans.single.body, contains('Netflix'));
      expect(plans.single.body, contains('12,99'));
    });

    test('si la hora de hoy ya pasó, salta a la siguiente ocurrencia', () {
      // Ocurrencia hoy con aviso a las 9:00, pero son las 12:00 → siguiente mes.
      final plans =
          planNotifications([rule(nextDate: DateTime(2026, 7, 8))], now: now);
      expect(plans, hasLength(1));
      expect(plans.single.when, DateTime(2026, 8, 8, 9, 0));
    });

    test('reglas desactivadas, sin aviso o borradas no se planifican', () {
      final deleted = rule(nextDate: DateTime(2026, 7, 15))
        ..deletedAt = DateTime(2026, 1, 1);
      final plans = planNotifications([
        rule(nextDate: DateTime(2026, 7, 15), enabled: false),
        rule(nextDate: DateTime(2026, 7, 15), active: false),
        deleted,
      ], now: now);
      expect(plans, isEmpty);
    });

    test('respeta la fecha de fin', () {
      final plans = planNotifications([
        rule(
          nextDate: DateTime(2026, 7, 8), // aviso de hoy ya pasado
          endDate: DateTime(2026, 7, 31), // y la siguiente (8 ago) queda fuera
        ),
      ], now: now);
      expect(plans, isEmpty);
    });

    test('texto según antelación', () {
      final today =
          planNotifications([rule(nextDate: DateTime(2026, 7, 9))], now: now);
      expect(today.single.body, startsWith('Hoy'));

      final before = planNotifications(
          [rule(nextDate: DateTime(2026, 7, 10), daysBefore: 1)],
          now: now);
      expect(before.single.body, startsWith('Mañana'));

      final custom = planNotifications(
          [rule(nextDate: DateTime(2026, 7, 20), daysBefore: 5)],
          now: now);
      expect(custom.single.body, startsWith('En 5 días'));
    });
  });
}
