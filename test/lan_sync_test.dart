import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/settings_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';
import 'package:finanzas/features/sync/model/sync_decisions.dart';
import 'package:finanzas/features/sync/net/lan_sync_client.dart';
import 'package:finanzas/features/sync/net/lan_sync_server.dart';
import 'package:finanzas/features/sync/net/sync_identity.dart';
import 'package:finanzas/features/sync/net/sync_protocol.dart';
import 'package:finanzas/features/sync/sync_engine.dart';
import 'package:finanzas/features/sync/sync_service.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Sync completo sobre HTTP real en loopback: emparejar → enviar changelog →
/// revisar/confirmar en el admin → reconciliar en el vinculado. Sin dispositivo.
void main() {
  setUpAll(initTestIsarCore);

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);

  late Isar adminDb;
  late Isar linkedDb;
  late SyncEngine adminEngine;
  late SyncEngine linkedEngine;
  late LanSyncServer server;
  late int port;

  setUp(() async {
    adminDb = await openTestIsar();
    linkedDb = await openTestIsar();
    adminEngine = SyncEngine(adminDb);
    linkedEngine = SyncEngine(linkedDb);
    final identity = await ensureIdentity(SettingsRepository(adminDb));
    server = LanSyncServer(
      isar: adminDb,
      engine: adminEngine,
      identity: identity,
      pin: '123456',
    );
    port = await server.start(port: 0); // puerto efímero
  });
  tearDown(() async {
    await server.stop();
    await adminDb.close(deleteFromDisk: true);
    await linkedDb.close(deleteFromDisk: true);
  });

  Future<Map<String, dynamic>> snapshot(SyncEngine e) async {
    final changes = await e.buildChangelog(epoch);
    return {
      for (final c in changes) c.uuid: {'deleted': c.isDeleted, 'data': c.data}
    };
  }

  test('emparejar + sincronizar deja ambas BD idénticas', () async {
    // El vinculado tiene datos.
    final accId =
        await AccountRepository(linkedDb).save(Account()..name = 'Banco');
    await TransactionRepository(linkedDb).save(TransactionModel()
      ..concept = 'Café'
      ..amountCents = 250
      ..accountId = accId
      ..date = DateTime(2026, 6, 1));

    final linked =
        LinkedSyncService(linkedDb, linkedEngine, SettingsRepository(linkedDb));

    // Emparejar con PIN.
    final adminName =
        await linked.pair(host: '127.0.0.1', port: port, pin: '123456');
    expect(adminName, isNotEmpty);

    // Lanzar el sync; en paralelo el admin confirma la sesión que le llega.
    final syncFuture = linked.sync(
      host: '127.0.0.1',
      port: port,
      pollInterval: const Duration(milliseconds: 20),
    );

    ReviewSession? pending;
    while (pending == null) {
      pending =
          server.debugSessions.isEmpty ? null : server.debugSessions.first;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(pending.plan.additions, hasLength(2));
    await server.finalizeSession(pending.id, SyncDecisions()); // aprobar todo

    final outcome = await syncFuture;
    expect(outcome.rejected, isFalse);
    expect(outcome.applied, greaterThan(0));

    expect(await snapshot(adminEngine), await snapshot(linkedEngine));
    expect(await adminDb.accounts.where().count(), 1);
  });

  test(
      'un pull vacío del vinculado trae los cambios propios del admin '
      '(bidireccional, sin que nadie confirme nada)', () async {
    final linked =
        LinkedSyncService(linkedDb, linkedEngine, SettingsRepository(linkedDb));
    await linked.pair(host: '127.0.0.1', port: port, pin: '123456');

    // El admin tiene cambios propios que el vinculado aún no vio.
    final accId =
        await AccountRepository(adminDb).save(Account()..name = 'Efectivo');
    await TransactionRepository(adminDb).save(TransactionModel()
      ..concept = 'Cena'
      ..amountCents = 1500
      ..accountId = accId
      ..date = DateTime(2026, 6, 2));

    // El vinculado no tiene nada propio que enviar: solo quiere ponerse al día.
    final outcome = await linked.sync(host: '127.0.0.1', port: port);

    expect(outcome.rejected, isFalse);
    expect(outcome.applied, greaterThan(0));
    expect(await linkedDb.accounts.where().count(), 1);
    expect(await linkedDb.transactions.where().count(), 1);
    // No debe haber quedado ninguna sesión pendiente de revisión en el admin.
    expect(
        server.debugSessions
            .every((s) => s.status != SyncSessionStatus.pending),
        isTrue);
  });

  test('rechaza el emparejamiento con PIN incorrecto', () async {
    final linked =
        LinkedSyncService(linkedDb, linkedEngine, SettingsRepository(linkedDb));
    expect(
      () => linked.pair(host: '127.0.0.1', port: port, pin: '000000'),
      throwsA(isA<LanSyncException>()
          .having((e) => e.statusCode, 'statusCode', 403)),
    );
  });

  test('rechaza peticiones de sync sin token válido', () async {
    final client = LanSyncClient(host: '127.0.0.1', port: port, token: 'malo');
    expect(
      () => client.pushChangelog(deviceId: 'x', changes: const []),
      throwsA(isA<LanSyncException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    client.close();
  });
}
