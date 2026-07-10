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

  test('CRUD de cuentas y categorías vía API (sellado + soft-delete)', () async {
    final c = client();
    await c.pair(pin: '424242', deviceId: 'pc', displayName: 'PC');

    final newAccId =
        await c.createAccount(AccountDto(name: 'Efectivo', type: AccountType.cash));
    expect(await c.accounts(), hasLength(2));
    expect((await db.accounts.get(newAccId))!.uuid, isNotEmpty);

    await c.updateAccount(
        newAccId, AccountDto(name: 'Cash', type: AccountType.cash));
    final updated = (await c.accounts()).firstWhere((a) => a.id == newAccId);
    expect(updated.name, 'Cash');

    await c.deleteAccount(newAccId);
    expect((await db.accounts.get(newAccId))!.deletedAt, isNotNull);

    final catId = await c.createCategory(
        CategoryDto(name: 'Ropa', kind: CategoryKind.expense));
    expect((await c.categories()).any((x) => x.id == catId), isTrue);
    await c.deleteCategory(catId);
    expect((await c.categories()).any((x) => x.id == catId), isFalse);
    c.close();
  });

  test('recurrentes, objetivos y ajustes vía API', () async {
    final c = client();
    await c.pair(pin: '424242', deviceId: 'pc', displayName: 'PC');

    final rid = await c.createRecurring(RecurringDto(
      name: 'Alquiler',
      amountCents: 50000,
      nextDate: DateTime(2030, 1, 1),
      accountId: accountId,
    ));
    expect((await c.recurring()).single.name, 'Alquiler');
    await c.deleteRecurring(rid);
    expect(await c.recurring(), isEmpty);

    final gid =
        await c.createGoal(GoalDto(name: 'Viaje', targetCents: 100000));
    expect((await c.goals()).single.name, 'Viaje');
    await c.deleteGoal(gid);
    expect(await c.goals(), isEmpty);

    final before = await c.getSettings();
    final after = await c.putSettings({'hideAmounts': !before.hideAmounts});
    expect(after.hideAmounts, !before.hideAmounts);
    c.close();
  });

  test('acciones masivas de movimientos', () async {
    final c = client();
    await c.pair(pin: '424242', deviceId: 'pc', displayName: 'PC');
    final catId = (await c.categories()).single.id;

    final id1 = await c.createTransaction(TransactionDto(
      type: TransactionType.expense,
      amountCents: 100,
      concept: 'a',
      date: DateTime(2026, 6, 1),
      accountId: accountId,
    ));
    final id2 = await c.createTransaction(TransactionDto(
      type: TransactionType.expense,
      amountCents: 200,
      concept: 'b',
      date: DateTime(2026, 6, 2),
      accountId: accountId,
    ));

    await c.batchTransactions('setCategory', [id1, id2], categoryId: catId);
    expect((await c.transactions()).every((t) => t.categoryId == catId), isTrue);

    await c.batchTransactions('delete', [id1, id2]);
    expect(await c.transactions(), isEmpty);
    c.close();
  });

  test('filtro de movimientos por tipo, importe y orden', () async {
    final c = client();
    await c.pair(pin: '424242', deviceId: 'pc', displayName: 'PC');

    await c.createTransaction(TransactionDto(
        type: TransactionType.expense,
        amountCents: 100,
        concept: 'barato',
        date: DateTime(2026, 6, 1),
        accountId: accountId));
    await c.createTransaction(TransactionDto(
        type: TransactionType.expense,
        amountCents: 900,
        concept: 'caro',
        date: DateTime(2026, 6, 2),
        accountId: accountId));
    await c.createTransaction(TransactionDto(
        type: TransactionType.income,
        amountCents: 5000,
        concept: 'nómina',
        date: DateTime(2026, 6, 3),
        accountId: accountId));

    final soloGastos =
        await c.transactions(types: {TransactionType.expense});
    expect(soloGastos, hasLength(2));

    final caros = await c.transactions(minCents: 500);
    expect(caros.map((t) => t.concept), containsAll(['caro', 'nómina']));

    final asc = await c.transactions(sort: WebTxSort.amountAsc);
    expect(asc.first.amountCents, 100);
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
