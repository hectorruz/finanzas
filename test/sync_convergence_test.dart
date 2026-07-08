import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/sync_peer.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';
import 'package:finanzas/features/sync/model/sync_decisions.dart';
import 'package:finanzas/features/sync/model/sync_plan.dart';
import 'package:finanzas/features/sync/sync_engine.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Convergencia extremo a extremo con dos dispositivos (dos instancias de Isar),
/// pasando listas de EntityChange entre ellos (sin red). Cubre los criterios de
/// aceptación de la fusión.
void main() {
  setUpAll(initTestIsarCore);

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);

  late Isar adminDb;
  late Isar linkedDb;
  late SyncEngine admin;
  late SyncEngine linked;
  late AccountRepository adminAccounts;
  late AccountRepository linkedAccounts;
  late TransactionRepository linkedTx;

  setUp(() async {
    adminDb = await openTestIsar();
    linkedDb = await openTestIsar();
    admin = SyncEngine(adminDb);
    linked = SyncEngine(linkedDb);
    adminAccounts = AccountRepository(adminDb);
    linkedAccounts = AccountRepository(linkedDb);
    linkedTx = TransactionRepository(linkedDb);
  });
  tearDown(() async {
    await adminDb.close(deleteFromDisk: true);
    await linkedDb.close(deleteFromDisk: true);
  });

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

  /// Ejecuta un sync completo vinculado→admin→vinculado y devuelve el plan que
  /// vio el admin.
  Future<SyncPlan> sync({
    required DateTime since,
    required DateTime newWatermark,
    SyncDecisions Function(SyncPlan)? decide,
  }) async {
    final incoming = await linked.buildChangelog(since);
    final own = await admin.buildChangelog(since);
    final plan = await admin.classifyIncoming(incoming, since);
    final result = await admin.mergeAsAdmin(
      incoming: incoming,
      ownChangelog: own,
      plan: plan,
      decisions: decide?.call(plan) ?? SyncDecisions(),
      newWatermark: newWatermark,
    );
    await linked.reconcileAsLinked(result.authoritative,
        newWatermark: newWatermark);
    return plan;
  }

  /// Foto comparable de una BD por uuid: estado de borrado + campos de dominio
  /// (las FKs ya son uuids, estables entre dispositivos).
  Future<Map<String, dynamic>> snapshot(SyncEngine e) async {
    final changes = await e.buildChangelog(epoch);
    return {
      for (final c in changes) c.uuid: {'deleted': c.isDeleted, 'data': c.data}
    };
  }

  test('alta nueva converge y resuelve la FK hacia adelante', () async {
    final accId = await linkedAccounts.save(Account()..name = 'Banco');
    await linkedTx.save(TransactionModel()
      ..concept = 'Café'
      ..amountCents = 250
      ..accountId = accId
      ..date = DateTime(2026, 6, 1));
    await tick();
    final w1 = DateTime.now();

    final plan = await sync(since: epoch, newWatermark: w1);
    expect(plan.additions, hasLength(2)); // cuenta + movimiento

    // El admin tiene ambos y la FK del movimiento apunta a SU cuenta.
    final adminTx = await adminDb.transactions.where().findAll();
    expect(adminTx, hasLength(1));
    final adminAcc = await adminDb.accounts.get(adminTx.single.accountId);
    expect(adminAcc, isNotNull);

    final linkedAcc = await linkedDb.accounts.get(accId);
    expect(adminAcc!.uuid, linkedAcc!.uuid,
        reason: 'misma cuenta lógica en ambos');
    expect(await snapshot(admin), await snapshot(linked));
  });

  test('borrar en el vinculado no resucita en el admin', () async {
    final accId = await linkedAccounts.save(Account()..name = 'Banco');
    final txId = await linkedTx.save(TransactionModel()
      ..concept = 'Café'
      ..amountCents = 250
      ..accountId = accId
      ..date = DateTime(2026, 6, 1));
    await tick();
    final w1 = DateTime.now();
    await sync(since: epoch, newWatermark: w1);

    await tick();
    await linkedTx.delete(txId); // el vinculado borra
    await tick();
    final w2 = DateTime.now();

    final plan = await sync(since: w1, newWatermark: w2);
    expect(plan.conflicts, isEmpty, reason: 'el admin no lo había tocado');

    // Ni el admin lo resucita ni queda vivo en el vinculado: tombstone en ambos.
    final adminTx = await adminDb.transactions
        .filter()
        .uuidEqualTo((await linkedDb.transactions.get(txId))!.uuid)
        .findFirst();
    expect(adminTx!.deletedAt, isNotNull);
    expect((await linkedDb.transactions.get(txId))!.deletedAt, isNotNull);
    expect(await snapshot(admin), await snapshot(linked));
  });

  test('editar la misma cuenta en ambos → conflicto; keepLocal revierte el vinculado',
      () async {
    final accId = await linkedAccounts.save(Account()..name = 'Orig');
    await tick();
    final w1 = DateTime.now();
    await sync(since: epoch, newWatermark: w1);
    await tick();

    // Ambos editan la misma cuenta (por uuid) después del watermark.
    final adminAccId = (await adminDb.accounts.where().findAll()).single.id;
    final adminAcc = await adminDb.accounts.get(adminAccId);
    await adminAccounts.save(adminAcc!..name = 'Admin');
    final linkedAcc = await linkedDb.accounts.get(accId);
    await linkedAccounts.save(linkedAcc!..name = 'Linked');
    await tick();
    final w2 = DateTime.now();

    final plan = await sync(
      since: w1,
      newWatermark: w2,
      decide: (p) => SyncDecisions(conflictChoices: {
        for (final c in p.conflicts) c.uuid: ConflictChoice.keepLocal,
      }),
    );

    expect(plan.conflicts, hasLength(1));
    expect((await adminDb.accounts.get(adminAccId))!.name, 'Admin');
    expect((await linkedDb.accounts.get(accId))!.name, 'Admin',
        reason: 'el vinculado revierte a la versión del admin');
    expect(await snapshot(admin), await snapshot(linked));
  });

  test('conflicto con keepRemote → ambos toman la versión del vinculado',
      () async {
    final accId = await linkedAccounts.save(Account()..name = 'Orig');
    await tick();
    final w1 = DateTime.now();
    await sync(since: epoch, newWatermark: w1);
    await tick();

    final adminAccId = (await adminDb.accounts.where().findAll()).single.id;
    await adminAccounts
        .save((await adminDb.accounts.get(adminAccId))!..name = 'Admin');
    await linkedAccounts
        .save((await linkedDb.accounts.get(accId))!..name = 'Linked');
    await tick();
    final w2 = DateTime.now();

    await sync(
      since: w1,
      newWatermark: w2,
      decide: (p) => SyncDecisions(conflictChoices: {
        for (final c in p.conflicts) c.uuid: ConflictChoice.keepRemote,
      }),
    );

    expect((await adminDb.accounts.get(adminAccId))!.name, 'Linked');
    expect((await linkedDb.accounts.get(accId))!.name, 'Linked');
    expect(await snapshot(admin), await snapshot(linked));
  });

  test('alta denegada → tombstone en ambos (se revierte, no se destruye)',
      () async {
    await linkedAccounts.save(Account()..name = 'Temporal');
    await tick();
    final w1 = DateTime.now();

    final plan = await sync(
      since: epoch,
      newWatermark: w1,
      decide: (p) => SyncDecisions(
          deniedUuids: p.additions.map((e) => e.uuid).toSet()),
    );
    expect(plan.additions, hasLength(1));

    // El admin la materializa como tombstone; el vinculado la retira.
    final adminAcc = (await adminDb.accounts.where().findAll());
    expect(adminAcc, hasLength(1));
    expect(adminAcc.single.deletedAt, isNotNull);
    final linkedActive = await linkedAccounts.all(includeArchived: true);
    expect(linkedActive, isEmpty, reason: 'ya no está viva en el vinculado');
    expect(await snapshot(admin), await snapshot(linked));
  });

  test('el watermark del par solo avanza tras aplicar (peerId)', () async {
    // Registrar el vinculado como par del admin.
    final peerId = await adminDb.writeTxn(
        () => adminDb.syncPeers.put(SyncPeer()..deviceId = 'linked-device'));
    await linkedAccounts.save(Account()..name = 'Banco');
    await tick();
    final w1 = DateTime.now();

    final incoming = await linked.buildChangelog(epoch);
    final plan = await admin.classifyIncoming(incoming, epoch);
    await admin.mergeAsAdmin(
      incoming: incoming,
      ownChangelog: const [],
      plan: plan,
      decisions: SyncDecisions(),
      newWatermark: w1,
      peerId: peerId,
    );

    final stored = await adminDb.syncPeers.get(peerId);
    expect(stored!.watermark, w1);
    expect(stored.lastSyncAt, isNotNull);
  });
}
