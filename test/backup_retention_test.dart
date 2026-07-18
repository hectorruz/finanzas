import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/features/backup/backup_retention.dart';
import 'package:finanzas/features/backup/cloud_backup_provider.dart';
import 'package:flutter_test/flutter_test.dart';

BackupEntry entry(String name) => BackupEntry(id: '/$name', name: name);

void main() {
  group('backupFilename', () {
    test('sigue el patrón esperado', () {
      final name = backupFilename(DateTime.utc(2026, 7, 17, 3, 30, 15));
      expect(name, 'finanzas_backup_2026-07-17T03-30-15Z.json');
      expect(isBackupFilename(name), isTrue);
    });

    test('convierte a UTC la hora local', () {
      final name = backupFilename(DateTime.utc(2026, 7, 17, 1).toLocal());
      expect(name, 'finanzas_backup_2026-07-17T01-00-00Z.json');
    });

    // La razón de ser del UTC: si el nombre llevara hora local, al retrasar el
    // reloj en otoño una copia posterior ordenaría antes que una anterior, y la
    // rotación borraría la copia equivocada.
    test('el orden lexicográfico coincide con el cronológico', () {
      final instants = [
        DateTime.utc(2026, 3, 29, 0, 30), // antes del cambio de horario
        DateTime.utc(2026, 3, 29, 1, 30), // durante
        DateTime.utc(2026, 10, 25, 0, 30), // el cambio de vuelta
        DateTime.utc(2026, 10, 25, 1, 30),
        DateTime.utc(2027, 1, 1),
      ];
      final names = instants.map(backupFilename).toList();
      final sorted = [...names]..sort();
      expect(sorted, names);
    });
  });

  group('isBackupFilename', () {
    test('acepta las nuestras', () {
      expect(isBackupFilename('finanzas_backup_2026-07-17T03-00-00Z.json'), isTrue);
    });

    test('rechaza ficheros ajenos', () {
      expect(isBackupFilename('fotos.json'), isFalse);
      expect(isBackupFilename('finanzas_backup_2026.txt'), isFalse);
      expect(isBackupFilename('presupuesto.xlsx'), isFalse);
      expect(isBackupFilename(''), isFalse);
    });
  });

  group('entriesToDelete', () {
    final copias = [
      entry('finanzas_backup_2026-07-15T03-00-00Z.json'),
      entry('finanzas_backup_2026-07-16T03-00-00Z.json'),
      entry('finanzas_backup_2026-07-17T03-00-00Z.json'),
    ];

    test('conserva las N más recientes y borra el resto', () {
      final borrar = entriesToDelete(copias, 2);
      expect(borrar.map((e) => e.name),
          ['finanzas_backup_2026-07-15T03-00-00Z.json']);
    });

    test('no borra nada si no se supera el límite', () {
      expect(entriesToDelete(copias, 3), isEmpty);
      expect(entriesToDelete(copias, 10), isEmpty);
    });

    test('keepLast <= 0 conserva todas', () {
      expect(entriesToDelete(copias, 0), isEmpty);
      expect(entriesToDelete(copias, -1), isEmpty);
    });

    test('lista vacía no revienta', () {
      expect(entriesToDelete([], 3), isEmpty);
    });

    test('NUNCA toca ficheros ajenos, aunque sobren copias', () {
      final mezcla = [
        entry('apuntes.txt'),
        entry('finanzas_backup_2026-07-15T03-00-00Z.json'),
        entry('foto.jpg'),
        entry('finanzas_backup_2026-07-16T03-00-00Z.json'),
        entry('finanzas_backup_2026-07-17T03-00-00Z.json'),
      ];
      final borrar = entriesToDelete(mezcla, 1);
      expect(borrar.map((e) => e.name), [
        'finanzas_backup_2026-07-15T03-00-00Z.json',
        'finanzas_backup_2026-07-16T03-00-00Z.json',
      ]);
      expect(borrar.any((e) => !isBackupFilename(e.name)), isFalse);
    });

    test('ordena por nombre, no por el orden de llegada del servidor', () {
      final desordenadas = [
        entry('finanzas_backup_2026-07-17T03-00-00Z.json'),
        entry('finanzas_backup_2026-07-15T03-00-00Z.json'),
        entry('finanzas_backup_2026-07-16T03-00-00Z.json'),
      ];
      expect(entriesToDelete(desordenadas, 1).map((e) => e.name), [
        'finanzas_backup_2026-07-15T03-00-00Z.json',
        'finanzas_backup_2026-07-16T03-00-00Z.json',
      ]);
    });
  });

  group('retentionHorizon', () {
    test('diaria: 10 copias son 10 días, no más', () {
      expect(retentionHorizon(BackupFrequency.daily, 1, 10).inDays, 10);
    });

    test('semanal y mensual escalan con la cadencia', () {
      expect(retentionHorizon(BackupFrequency.weekly, 1, 4).inDays, 28);
      expect(retentionHorizon(BackupFrequency.monthly, 1, 12).inDays, 360);
      expect(retentionHorizon(BackupFrequency.monthly, 3, 4).inDays, 360);
    });

    test('valores inválidos se tratan como 1', () {
      expect(retentionHorizon(BackupFrequency.daily, 0, 0).inDays, 1);
    });
  });

  group('retentionHorizonLabel', () {
    test('elige la unidad legible', () {
      expect(retentionHorizonLabel(BackupFrequency.daily, 1, 10),
          '≈ 10 días de historial');
      expect(retentionHorizonLabel(BackupFrequency.daily, 1, 1),
          '≈ 1 día de historial');
      expect(retentionHorizonLabel(BackupFrequency.weekly, 1, 4),
          '≈ 4 semanas de historial');
      expect(retentionHorizonLabel(BackupFrequency.monthly, 1, 12),
          '≈ 12 meses de historial');
      expect(retentionHorizonLabel(BackupFrequency.monthly, 3, 10),
          '≈ 2 años de historial');
    });
  });
}
