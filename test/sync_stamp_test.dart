import 'package:finanzas/core/sync/sync_stamp.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests puros del sellado de sincronización (no tocan Isar).
void main() {
  group('stampForSave', () {
    test('genera uuid solo la primera vez y fija updatedAt', () {
      final t = TransactionModel();
      expect(t.uuid, isEmpty);

      final t0 = DateTime(2026, 1, 1, 10);
      stampForSave(t, now: t0);

      expect(t.uuid, isNotEmpty);
      expect(t.updatedAt, t0);
      expect(t.deletedAt, isNull);
    });

    test('conserva el uuid en ediciones sucesivas y bumpea updatedAt', () {
      final t = TransactionModel();
      stampForSave(t, now: DateTime(2026, 1, 1));
      final firstUuid = t.uuid;

      stampForSave(t, now: DateTime(2026, 1, 2));

      expect(t.uuid, firstUuid, reason: 'el uuid es estable');
      expect(t.updatedAt, DateTime(2026, 1, 2));
      expect(t.deletedAt, isNull, reason: 'guardar no borra');
    });

    test('genera uuids distintos para entidades distintas', () {
      final a = TransactionModel();
      final b = TransactionModel();
      stampForSave(a);
      stampForSave(b);
      expect(a.uuid, isNot(b.uuid));
    });
  });

  group('stampForDelete', () {
    test('fija deletedAt y updatedAt al mismo instante', () {
      final t = TransactionModel();
      stampForSave(t, now: DateTime(2026, 1, 1));
      final uuid = t.uuid;

      final at = DateTime(2026, 3, 4, 9);
      stampForDelete(t, now: at);

      expect(t.deletedAt, at);
      expect(t.updatedAt, at);
      expect(t.uuid, uuid, reason: 'borrar no cambia la identidad');
    });

    test('garantiza uuid aunque se borre una entidad sin sellar', () {
      final t = TransactionModel();
      expect(t.uuid, isEmpty);
      stampForDelete(t, now: DateTime(2026, 1, 1));
      expect(t.uuid, isNotEmpty);
      expect(t.deletedAt, isNotNull);
    });
  });
}
