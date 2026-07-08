import 'package:finanzas/data/repositories/merchant_rule_repository.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_isar.dart';

/// Memoria de correcciones del OCR (comercio → categoría).
void main() {
  setUpAll(initTestIsarCore);

  late Isar db;
  late MerchantRuleRepository repo;
  setUp(() async {
    db = await openTestIsar();
    repo = MerchantRuleRepository(db);
  });
  tearDown(() async => db.close(deleteFromDisk: true));

  test('recuerda y recupera normalizando el comercio', () async {
    await repo.remember('  Mercadona   S.A. ', 7);
    expect(await repo.categoryFor('mercadona s.a.'), 7);
    expect(await repo.categoryFor('MERCADONA S.A.'), 7);
    expect(await repo.categoryFor('otro sitio'), isNull);
  });

  test('una corrección posterior sustituye la categoría', () async {
    await repo.remember('Mercadona', 7);
    await repo.remember('Mercadona', 9); // el usuario corrige
    expect(await repo.categoryFor('Mercadona'), 9);
  });

  test('forget elimina la asociación', () async {
    await repo.remember('Mercadona', 7);
    await repo.forget('Mercadona');
    expect(await repo.categoryFor('Mercadona'), isNull);
  });

  test('comercio vacío no guarda nada', () async {
    await repo.remember('   ', 7);
    expect(await repo.categoryFor(''), isNull);
  });
}
