import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/category.dart';
import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/category_repository.dart';
import 'package:finanzas/features/sync/net/lan_sync_server.dart';
import 'package:finanzas/features/sync/net/sync_identity.dart';
import 'package:finanzas/data/repositories/settings_repository.dart';
import 'package:finanzas/features/sync/sync_engine.dart';
import 'package:finanzas/features/web/web_api_client.dart';
import 'package:finanzas/features/web/web_models.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// La API de datos de la webapp sobre HTTP real: emparejar, listar, crear y
/// borrar movimientos, con token obligatorio.
void main() {
  setUpAll(initTestIsarCore);

  late Isar db;
  late LanSyncServer server;
  late int port;
  late int accountId;

  setUp(() async {
    db = await openTestIsar();
    accountId = await AccountRepository(db).save(Account()..name = 'Banco');
    await CategoryRepository(db)
        .save(Category()..name = 'Comida'..kind = CategoryKind.expense);
    final identity = await ensureIdentity(SettingsRepository(db));
    server = LanSyncServer(
      isar: db,
      engine: SyncEngine(db),
      identity: identity,
      pin: '424242',
    );
    port = await server.start(port: 0);
  });
  tearDown(() async {
    await server.stop();
    await db.close(deleteFromDisk: true);
  });

  WebApiClient client({String? token}) => WebApiClient(
        baseUri: Uri(scheme: 'http', host: '127.0.0.1', port: port),
        token: token,
      );

  test('emparejar y operar con la API (listar, crear, borrar)', () async {
    final c = client();
    await c.pair(pin: '424242', deviceId: 'pc', displayName: 'PC');

    final accounts = await c.accounts();
    expect(accounts, hasLength(1));
    expect(accounts.single.name, 'Banco');

    final categories = await c.categories();
    expect(categories.single.name, 'Comida');

    expect(await c.transactions(), isEmpty);

    final id = await c.createTransaction(TransactionDto(
      type: TransactionType.expense,
      amountCents: 1599,
      concept: 'Menú',
      date: DateTime(2026, 6, 1),
      accountId: accountId,
      categoryId: categories.single.id,
    ));

    final list = await c.transactions();
    expect(list, hasLength(1));
    expect(list.single.amountCents, 1599);

    // El movimiento creado por la API pasa por el repo: queda sellado para sync.
    expect((await db.transactions.get(id))!.uuid, isNotEmpty);

    await c.deleteTransaction(id);
    expect(await c.transactions(), isEmpty);
    // Borrado lógico: la fila sigue con tombstone.
    expect((await db.transactions.get(id))!.deletedAt, isNotNull);
    c.close();
  });

  test('la API rechaza peticiones sin token válido', () async {
    final c = client(token: 'malo');
    expect(
      () => c.accounts(),
      throwsA(isA<WebApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    c.close();
  });
}
