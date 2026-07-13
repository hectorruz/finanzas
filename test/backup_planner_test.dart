import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/features/backup/backup_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isBackupDue', () {
    test('sin copia previa → siempre toca', () {
      expect(
        isBackupDue(
            freq: BackupFrequency.weekly, lastRun: null, now: DateTime(2026)),
        isTrue,
      );
    });

    test('diaria: copia hace 25 h → toca', () {
      final now = DateTime(2026, 7, 13, 10);
      final last = now.subtract(const Duration(hours: 25));
      expect(isBackupDue(freq: BackupFrequency.daily, lastRun: last, now: now),
          isTrue);
    });

    test('diaria: copia hace 5 h → no toca', () {
      final now = DateTime(2026, 7, 13, 10);
      final last = now.subtract(const Duration(hours: 5));
      expect(isBackupDue(freq: BackupFrequency.daily, lastRun: last, now: now),
          isFalse);
    });

    test('semanal: copia hace 6 días → no toca; hace 7 → toca', () {
      final now = DateTime(2026, 7, 13, 10);
      expect(
        isBackupDue(
            freq: BackupFrequency.weekly,
            lastRun: now.subtract(const Duration(days: 6)),
            now: now),
        isFalse,
      );
      expect(
        isBackupDue(
            freq: BackupFrequency.weekly,
            lastRun: now.subtract(const Duration(days: 7)),
            now: now),
        isTrue,
      );
    });

    test('mensual: copia hace 29 días → no toca; hace 30 → toca', () {
      final now = DateTime(2026, 7, 13, 10);
      expect(
        isBackupDue(
            freq: BackupFrequency.monthly,
            lastRun: now.subtract(const Duration(days: 29)),
            now: now),
        isFalse,
      );
      expect(
        isBackupDue(
            freq: BackupFrequency.monthly,
            lastRun: now.subtract(const Duration(days: 30)),
            now: now),
        isTrue,
      );
    });
  });

  group('nextBackupTime', () {
    test('sin copia previa, hora de hoy aún futura → hoy a esa hora', () {
      final now = DateTime(2026, 7, 13, 1, 0); // 01:00
      final next = nextBackupTime(
          freq: BackupFrequency.daily, hour: 3, lastRun: null, now: now);
      expect(next, DateTime(2026, 7, 13, 3, 0));
    });

    test('sin copia previa, hora de hoy ya pasada → mañana a esa hora', () {
      final now = DateTime(2026, 7, 13, 5, 0); // 05:00, ya pasaron las 03:00
      final next = nextBackupTime(
          freq: BackupFrequency.daily, hour: 3, lastRun: null, now: now);
      expect(next, DateTime(2026, 7, 14, 3, 0));
    });

    test('semanal con copia previa → una semana después a la hora preferida', () {
      final now = DateTime(2026, 7, 13, 12, 0);
      final last = DateTime(2026, 7, 10, 3, 0); // 3 días atrás
      final next = nextBackupTime(
          freq: BackupFrequency.weekly, hour: 3, lastRun: last, now: now);
      expect(next, DateTime(2026, 7, 17, 3, 0)); // 10 + 7 = 17
    });

    test('siempre estrictamente futura', () {
      final now = DateTime(2026, 7, 13, 12, 0);
      final next = nextBackupTime(
          freq: BackupFrequency.daily, hour: 3, lastRun: null, now: now);
      expect(next.isAfter(now), isTrue);
    });
  });
}
