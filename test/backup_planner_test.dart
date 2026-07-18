import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/features/backup/backup_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('daysInMonth', () {
    test('meses de 31, 30 y febrero', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 2), 28);
    });

    test('febrero en año bisiesto', () {
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2000, 2), 29); // divisible por 400
      expect(daysInMonth(1900, 2), 28); // divisible por 100 pero no por 400
    });
  });

  group('addMonthsClamped', () {
    test('recorta el día al último del mes destino', () {
      expect(
        addMonthsClamped(DateTime(2026, 1, 31, 3), 1),
        DateTime(2026, 2, 28, 3),
      );
      expect(
        addMonthsClamped(DateTime(2026, 3, 31, 3), 1),
        DateTime(2026, 4, 30, 3),
      );
    });

    test('en bisiesto recorta a 29 de febrero', () {
      expect(
        addMonthsClamped(DateTime(2028, 1, 31, 3), 1),
        DateTime(2028, 2, 29, 3),
      );
    });

    test('no toca el día si cabe en el mes destino', () {
      expect(
        addMonthsClamped(DateTime(2026, 1, 15, 3, 30), 1),
        DateTime(2026, 2, 15, 3, 30),
      );
    });

    test('cruza el fin de año', () {
      expect(
        addMonthsClamped(DateTime(2026, 11, 30, 3), 3),
        DateTime(2027, 2, 28, 3),
      );
    });

    test('conserva la hora', () {
      final r = addMonthsClamped(DateTime(2026, 1, 31, 3, 45), 1);
      expect(r.hour, 3);
      expect(r.minute, 45);
    });
  });

  group('occurrenceAt', () {
    test('diaria avanza de día en día', () {
      final anchor = DateTime(2026, 7, 17, 3);
      expect(occurrenceAt(anchor: anchor, freq: BackupFrequency.daily, every: 1, n: 0), anchor);
      expect(
        occurrenceAt(anchor: anchor, freq: BackupFrequency.daily, every: 1, n: 3),
        DateTime(2026, 7, 20, 3),
      );
    });

    test('semanal avanza de 7 en 7 días', () {
      expect(
        occurrenceAt(
            anchor: DateTime(2026, 7, 17, 3),
            freq: BackupFrequency.weekly,
            every: 1,
            n: 2),
        DateTime(2026, 7, 31, 3),
      );
    });

    test('"cada N" multiplica el paso', () {
      expect(
        occurrenceAt(
            anchor: DateTime(2026, 7, 17, 3),
            freq: BackupFrequency.daily,
            every: 3,
            n: 2),
        DateTime(2026, 7, 23, 3),
      );
    });

    // El bug que motiva el diseño anclado: encadenar desde la ocurrencia previa
    // haría 31 ene → 28 feb → 28 mar → 28 abr (el día se adelanta para siempre).
    test('mensual desde el día 31 NO deriva (sin trinquete)', () {
      final anchor = DateTime(2026, 1, 31, 3);
      DateTime at(int n) => occurrenceAt(
          anchor: anchor, freq: BackupFrequency.monthly, every: 1, n: n);
      expect(at(0), DateTime(2026, 1, 31, 3));
      expect(at(1), DateTime(2026, 2, 28, 3));
      expect(at(2), DateTime(2026, 3, 31, 3), reason: 'vuelve al 31, no se queda en 28');
      expect(at(3), DateTime(2026, 4, 30, 3));
      expect(at(4), DateTime(2026, 5, 31, 3));
    });

    test('trimestral es monthly con every: 3', () {
      final anchor = DateTime(2026, 1, 31, 3);
      DateTime at(int n) => occurrenceAt(
          anchor: anchor, freq: BackupFrequency.monthly, every: 3, n: n);
      expect(at(0), DateTime(2026, 1, 31, 3));
      expect(at(1), DateTime(2026, 4, 30, 3));
      expect(at(2), DateTime(2026, 7, 31, 3));
      expect(at(3), DateTime(2026, 10, 31, 3));
      expect(at(4), DateTime(2027, 1, 31, 3));
    });

    // Madrid pasa a horario de verano el 29 de marzo de 2026 a las 02:00, y con
    // `add(Duration(days: 1))` la copia de las 03:00 se iría a las 04:00.
    // Ojo: este test solo es load-bearing si la máquina está en una zona con
    // cambio de horario; en UTC pasaría igual con la implementación mala. Se
    // mantiene porque el entorno de desarrollo es Europe/Madrid, pero la
    // garantía de verdad es usar el constructor de DateTime en `occurrenceAt`.
    test('la hora de pared aguanta el cambio de horario de verano', () {
      final anchor = DateTime(2026, 3, 28, 3);
      for (var n = 0; n < 5; n++) {
        final o = occurrenceAt(
            anchor: anchor, freq: BackupFrequency.daily, every: 1, n: n);
        expect(o.hour, 3, reason: 'ocurrencia $n debería seguir a las 03:00');
      }
    });
  });

  group('nextOccurrenceAfter', () {
    final anchor = DateTime(2026, 1, 31, 3);

    test('devuelve la siguiente estrictamente futura', () {
      expect(
        nextOccurrenceAfter(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            after: DateTime(2026, 2, 10)),
        DateTime(2026, 2, 28, 3),
      );
    });

    test('en la ocurrencia exacta devuelve la siguiente, no la misma', () {
      expect(
        nextOccurrenceAfter(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            after: DateTime(2026, 2, 28, 3)),
        DateTime(2026, 3, 31, 3),
      );
    });

    test('con "after" anterior al ancla devuelve el propio ancla', () {
      expect(
        nextOccurrenceAfter(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            after: DateTime(2025, 12, 1)),
        anchor,
      );
    });

    test('tras un hueco largo salta a la ocurrencia correcta', () {
      expect(
        nextOccurrenceAfter(
            anchor: anchor,
            freq: BackupFrequency.daily,
            every: 1,
            after: DateTime(2026, 6, 15, 10)),
        DateTime(2026, 6, 16, 3),
      );
    });

    test('el recorte de fin de mes no adelanta la serie', () {
      // Partiendo de la ocurrencia recortada (28 feb), la siguiente es 31 mar.
      expect(
        nextOccurrenceAfter(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            after: DateTime(2026, 2, 28, 3, 1)),
        DateTime(2026, 3, 31, 3),
      );
    });
  });

  group('isBackupDue', () {
    final anchor = DateTime(2026, 1, 31, 3);

    test('sin copia previa siempre toca', () {
      expect(
        isBackupDue(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            lastRun: null,
            now: DateTime(2026, 1, 1)),
        isTrue,
      );
    });

    test('no toca si la siguiente ocurrencia aún no ha llegado', () {
      expect(
        isBackupDue(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            lastRun: DateTime(2026, 1, 31, 3),
            now: DateTime(2026, 2, 20)),
        isFalse,
      );
    });

    test('toca cuando se pasa la siguiente ocurrencia', () {
      expect(
        isBackupDue(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 1,
            lastRun: DateTime(2026, 1, 31, 3),
            now: DateTime(2026, 2, 28, 4)),
        isTrue,
      );
    });

    test('diaria: copia de ayer → toca hoy', () {
      final a = DateTime(2026, 7, 1, 3);
      expect(
        isBackupDue(
            anchor: a,
            freq: BackupFrequency.daily,
            every: 1,
            lastRun: DateTime(2026, 7, 16, 3),
            now: DateTime(2026, 7, 17, 10)),
        isTrue,
      );
    });

    test('trimestral: al mes de la última copia no toca', () {
      expect(
        isBackupDue(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 3,
            lastRun: DateTime(2026, 1, 31, 3),
            now: DateTime(2026, 2, 28)),
        isFalse,
      );
    });

    test('trimestral: a los tres meses toca', () {
      expect(
        isBackupDue(
            anchor: anchor,
            freq: BackupFrequency.monthly,
            every: 3,
            lastRun: DateTime(2026, 1, 31, 3),
            now: DateTime(2026, 4, 30, 4)),
        isTrue,
      );
    });
  });

  group('reanchor', () {
    test('cambia la hora conservando el día', () {
      expect(
        reanchor(DateTime(2026, 1, 31, 3, 0), 22, 30),
        DateTime(2026, 1, 31, 22, 30),
      );
    });
  });

  group('frequencyLabel', () {
    test('las cadencias con nombre propio', () {
      expect(frequencyLabel(BackupFrequency.daily, 1), 'Diaria');
      expect(frequencyLabel(BackupFrequency.weekly, 1), 'Semanal');
      expect(frequencyLabel(BackupFrequency.monthly, 1), 'Mensual');
      expect(frequencyLabel(BackupFrequency.monthly, 3), 'Trimestral');
      expect(frequencyLabel(BackupFrequency.monthly, 6), 'Semestral');
      expect(frequencyLabel(BackupFrequency.monthly, 12), 'Anual');
    });

    test('las personalizadas caen en "Cada N …"', () {
      expect(frequencyLabel(BackupFrequency.daily, 3), 'Cada 3 días');
      expect(frequencyLabel(BackupFrequency.weekly, 2), 'Cada 2 semanas');
      expect(frequencyLabel(BackupFrequency.monthly, 4), 'Cada 4 meses');
    });

    test('every inválido se trata como 1', () {
      expect(frequencyLabel(BackupFrequency.daily, 0), 'Diaria');
    });
  });

  group('presetFor', () {
    test('reconoce trimestral', () {
      expect(presetFor(BackupFrequency.monthly, 3), isNotNull);
      expect(kBackupPresets[presetFor(BackupFrequency.monthly, 3)!].every, 3);
    });

    test('una cadencia sin nombre propio es personalizada', () {
      expect(presetFor(BackupFrequency.monthly, 4), isNull);
      expect(presetFor(BackupFrequency.daily, 5), isNull);
    });
  });
}
