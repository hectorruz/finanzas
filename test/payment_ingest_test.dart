import 'dart:convert';

import 'package:finanzas/data/models/account.dart';
import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/repositories/account_repository.dart';
import 'package:finanzas/data/repositories/settings_repository.dart';
import 'package:finanzas/data/repositories/transaction_repository.dart';
import 'package:finanzas/features/payments/payment_ingest_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'support/test_isar.dart';

/// Ingesta de pagos: el camino que recorre el engine headless con la app
/// cerrada (drenar el buffer nativo → parsear → crear el gasto).
///
/// El canal nativo se simula: aquí solo se comprueba la lógica Dart. `_notify`
/// se desactiva solo (sin plugin, `ensureNotificationsInitialized()` da false).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestIsarCore);

  const channel = MethodChannel('com.example.finanzas/payments');

  late Isar db;
  late PaymentIngestService service;
  late int accountId;

  /// Lo que devolverá el `drainBuffer` simulado en la próxima llamada.
  List<Map<String, dynamic>> buffer = [];

  /// Cuántas veces se ha drenado (el buffer real se vacía al leerlo).
  var drains = 0;

  setUp(() async {
    db = await openTestIsar();
    service = PaymentIngestService(db);
    buffer = [];
    drains = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'drainBuffer':
          drains++;
          final data = jsonEncode(buffer);
          buffer = []; // igual que el nativo: leer vacía
          return data;
        case 'peekBuffer':
          return jsonEncode(buffer);
        default:
          return null;
      }
    });

    final account = Account()
      ..name = 'Cuenta principal'
      ..type = AccountType.bank;
    accountId = await AccountRepository(db).save(account);
    await SettingsRepository(db).update((s) {
      s.paymentReaderEnabled = true;
      s.paymentDefaultAccountId = accountId;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close(deleteFromDisk: true);
  });

  Map<String, dynamic> walletPayment({
    required String title,
    required String text,
    DateTime? at,
  }) =>
      {
        'package': 'com.google.android.apps.walletnfcrel',
        'title': title,
        'text': text,
        'postedAt': (at ?? DateTime(2026, 7, 16, 12)).millisecondsSinceEpoch,
      };

  test('crea el gasto de un pago de Wallet', () async {
    buffer = [walletPayment(title: 'MERCADONA', text: '23,45 € · Visa ••1234')];

    expect(await service.drainAndProcess(), 1);

    final txns = await TransactionRepository(db).query(TransactionFilter());
    expect(txns, hasLength(1));
    expect(txns.first.amountCents, 2345);
    expect(txns.first.concept, 'Mercadona'); // supermercado conocido: canónico
    expect(txns.first.type, TransactionType.expense);
    expect(txns.first.accountId, accountId);
    expect(txns.first.note, 'Tarjeta ••1234');
  });

  test('no duplica si la misma notificación se procesa dos veces', () async {
    final payment =
        walletPayment(title: 'MERCADONA', text: '23,45 € · Visa ••1234');
    buffer = [payment];
    expect(await service.drainAndProcess(), 1);

    // El nativo vuelve a capturar el mismo pago (p. ej. Wallet actualiza la
    // notificación y el engine se dispara otra vez).
    buffer = [payment];
    expect(await service.drainAndProcess(), 0,
        reason: 'la huella ya procesada debe frenarlo');

    final txns = await TransactionRepository(db).query(TransactionFilter());
    expect(txns, hasLength(1));
  });

  test('con el lector apagado no crea nada ni toca el buffer', () async {
    await SettingsRepository(db).update((s) => s.paymentReaderEnabled = false);
    buffer = [walletPayment(title: 'MERCADONA', text: '23,45 €')];

    expect(await service.drainAndProcess(), 0);
    expect(drains, 0, reason: 'ni siquiera debe drenar');
    expect(await TransactionRepository(db).query(TransactionFilter()), isEmpty);
  });

  test('ignora una notificación que no es un pago', () async {
    buffer = [
      walletPayment(title: 'Google Wallet', text: 'Añade una tarjeta nueva'),
    ];

    expect(await service.drainAndProcess(), 0);
    expect(await TransactionRepository(db).query(TransactionFilter()), isEmpty);
  });

  test('procesa varios pagos capturados de una tacada', () async {
    buffer = [
      walletPayment(title: 'MERCADONA', text: '23,45 €'),
      walletPayment(title: 'LIDL', text: '9,99 €'),
    ];

    expect(await service.drainAndProcess(), 2);
    expect(await TransactionRepository(db).query(TransactionFilter()),
        hasLength(2));
  });
}
