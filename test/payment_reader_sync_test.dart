import 'package:finanzas/data/repositories/settings_repository.dart';
import 'package:finanzas/features/payments/notification_parser.dart';
import 'package:finanzas/features/payments/payment_reader_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'support/test_isar.dart';

/// Espejo de los ajustes hacia el servicio nativo. Es el gate que decide si un
/// pago arranca el engine de ingesta con la app cerrada: si el espejo miente, o
/// se pierden pagos o se arranca un engine por cada notificación para nada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestIsarCore);

  const channel = MethodChannel('com.example.finanzas/payments');

  late Isar db;
  late SettingsRepository repo;
  final calls = <MethodCall>[];

  setUp(() async {
    db = await openTestIsar();
    repo = SettingsRepository(db);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close(deleteFromDisk: true);
  });

  MethodCall? callTo(String method) =>
      calls.where((c) => c.method == method).firstOrNull;

  test('con el lector activo espeja true y manda los paquetes', () async {
    await repo.update((s) => s.paymentReaderEnabled = true);

    await syncPaymentReaderToNative(repo);

    expect(callTo('setReaderEnabled')?.arguments, isTrue);
    expect(callTo('setSourcePackages')?.arguments,
        contains(NotificationRule.walletPackage));
  });

  test('con el lector apagado espeja false', () async {
    await repo.update((s) => s.paymentReaderEnabled = false);

    await syncPaymentReaderToNative(repo);

    expect(callTo('setReaderEnabled')?.arguments, isFalse,
        reason: 'sin esto el nativo seguiría arrancando engines');
  });

  test('las apps del usuario se añaden a Wallet como origen', () async {
    await repo.update((s) {
      s.paymentReaderEnabled = true;
      s.notificationAppRules = [
        const NotificationRule(package: 'com.banco.app', label: 'Mi Banco')
            .encode(),
      ];
    });

    await syncPaymentReaderToNative(repo);

    expect(
      callTo('setSourcePackages')?.arguments,
      containsAll([NotificationRule.walletPackage, 'com.banco.app']),
    );
  });

  group('paymentSourcePackages', () {
    test('Wallet siempre está, aunque no haya reglas', () {
      expect(paymentSourcePackages([]), [NotificationRule.walletPackage]);
    });

    test('descarta reglas corruptas sin romperse', () {
      final packages = paymentSourcePackages([
        'esto no es json',
        const NotificationRule(package: 'com.banco.app', label: 'B').encode(),
      ]);
      expect(packages, containsAll(['com.banco.app']));
      expect(packages, hasLength(2));
    });

    test('no repite un paquete duplicado', () {
      final packages = paymentSourcePackages([
        const NotificationRule(
                package: NotificationRule.walletPackage, label: 'W')
            .encode(),
      ]);
      expect(packages, hasLength(1));
    });
  });
}
