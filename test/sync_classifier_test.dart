import 'package:finanzas/features/sync/model/entity_change.dart';
import 'package:finanzas/features/sync/model/sync_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests puros del clasificador: el timestamp solo detecta el cambio; el
/// conflicto lo decide una persona, nunca el reloj.
void main() {
  final watermark = DateTime(2026, 1, 1);

  EntityChange change(
    String uuid, {
    required DateTime updatedAt,
    DateTime? deletedAt,
    Map<String, dynamic>? data,
  }) =>
      EntityChange(
        collection: SyncCollection.transaction,
        uuid: uuid,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        data: data ?? {'amountCents': 100, 'concept': 'x'},
      );

  test('uuid desconocido para el admin → addition', () {
    final plan = classifyChanges(
      incoming: [change('new', updatedAt: DateTime(2026, 2, 1))],
      localByUuid: {},
      watermark: watermark,
    );
    expect(plan.additions.map((e) => e.uuid), ['new']);
    expect(plan.cleanUpdates, isEmpty);
    expect(plan.conflicts, isEmpty);
  });

  test('existe y el admin no lo tocó desde el watermark → cleanUpdate', () {
    final local = change('a', updatedAt: DateTime(2025, 12, 1)); // < watermark
    final remote =
        change('a', updatedAt: DateTime(2026, 2, 1), data: {'amountCents': 200});
    final plan = classifyChanges(
      incoming: [remote],
      localByUuid: {'a': local},
      watermark: watermark,
    );
    expect(plan.cleanUpdates.map((e) => e.uuid), ['a']);
    expect(plan.conflicts, isEmpty);
  });

  test('ambos lo tocaron desde el watermark → conflicto', () {
    final local =
        change('a', updatedAt: DateTime(2026, 1, 5), data: {'amountCents': 111});
    final remote =
        change('a', updatedAt: DateTime(2026, 1, 6), data: {'amountCents': 222});
    final plan = classifyChanges(
      incoming: [remote],
      localByUuid: {'a': local},
      watermark: watermark,
    );
    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.local.data['amountCents'], 111);
    expect(plan.conflicts.single.remote.data['amountCents'], 222);
    expect(plan.cleanUpdates, isEmpty);
  });

  test('uno lo borró y el otro lo editó → conflicto', () {
    final local =
        change('a', updatedAt: DateTime(2026, 1, 5), data: {'amountCents': 111});
    final remoteDeleted = change('a',
        updatedAt: DateTime(2026, 1, 6), deletedAt: DateTime(2026, 1, 6));
    final plan = classifyChanges(
      incoming: [remoteDeleted],
      localByUuid: {'a': local},
      watermark: watermark,
    );
    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.remote.isDeleted, isTrue);
    expect(plan.conflicts.single.local.isDeleted, isFalse);
  });

  test('versiones idénticas (convergieron por su cuenta) → se descarta', () {
    final data = {'amountCents': 500, 'concept': 'igual'};
    final local = change('a', updatedAt: DateTime(2026, 1, 5), data: data);
    final remote = change('a', updatedAt: DateTime(2026, 1, 9), data: data);
    final plan = classifyChanges(
      incoming: [remote],
      localByUuid: {'a': local},
      watermark: watermark,
    );
    expect(plan.isEmpty, isTrue);
  });

  test('un borrado que el admin no tiene sigue siendo addition (tombstone)', () {
    final plan = classifyChanges(
      incoming: [
        change('ghost',
            updatedAt: DateTime(2026, 2, 1), deletedAt: DateTime(2026, 2, 1))
      ],
      localByUuid: {},
      watermark: watermark,
    );
    expect(plan.additions.single.isDeleted, isTrue);
  });
}
