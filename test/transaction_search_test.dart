import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/category.dart';
import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/category_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// La búsqueda de texto del filtro coincide con concepto/nota y —cuando se le
/// pasan los mapas id→nombre— también con el nombre de cuenta y categoría.
void main() {
  setUpAll(initTestIsarCore);

  late Isar isar;
  late TransactionRepository txns;
  late AccountRepository accounts;
  late CategoryRepository categories;
  setUp(() async {
    isar = await openTestIsar();
    txns = TransactionRepository(isar);
    accounts = AccountRepository(isar);
    categories = CategoryRepository(isar);
  });
  tearDown(() async => isar.close(deleteFromDisk: true));

  test('busca por concepto y nota, y por nombre de cuenta/categoría', () async {
    final banco = await accounts.save(Account()..name = 'Banco Azul');
    final efectivo = await accounts.save(Account()..name = 'Efectivo');
    final comida = await categories.save(Category()..name = 'Comida');
    final ocio = await categories.save(Category()..name = 'Ocio');

    final tCafe = await txns.save(TransactionModel()
      ..concept = 'Café mañana'
      ..amountCents = 250
      ..accountId = banco
      ..categoryId = ocio
      ..date = DateTime(2026, 6, 1));
    final tMercadona = await txns.save(TransactionModel()
      ..concept = 'Compra'
      ..note = 'semana'
      ..amountCents = 4500
      ..accountId = efectivo
      ..categoryId = comida
      ..date = DateTime(2026, 6, 2));

    final accountNames = {banco: 'Banco Azul', efectivo: 'Efectivo'};
    final categoryNames = {comida: 'Comida', ocio: 'Ocio'};

    Future<List<int>> search(String q) async {
      final r = await txns.query(
        TransactionFilter(query: q),
        accountNames: accountNames,
        categoryNames: categoryNames,
      );
      return r.map((t) => t.id).toList();
    }

    // Por concepto.
    expect(await search('café'), [tCafe]);
    // Por nota.
    expect(await search('semana'), [tMercadona]);
    // Por nombre de categoría.
    expect(await search('comida'), [tMercadona]);
    // Por nombre de cuenta (insensible a mayúsculas).
    expect(await search('banco'), [tCafe]);
    // Sin coincidencias.
    expect(await search('inexistente'), isEmpty);
  });

  test('sin mapas de nombres, solo coincide por concepto/nota', () async {
    final acc = await accounts.save(Account()..name = 'Nómina');
    await txns.save(TransactionModel()
      ..concept = 'Sueldo'
      ..accountId = acc
      ..date = DateTime(2026, 6, 1));

    // 'nómina' es el nombre de la cuenta, pero sin accountNames no coincide.
    final r = await txns.query(const TransactionFilter(query: 'nómina'));
    expect(r, isEmpty);
  });
}
