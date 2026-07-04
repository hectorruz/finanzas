import 'package:flutter_test/flutter_test.dart';
import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/data/models/transaction.dart';

void main() {
  group('TransactionModel.signedCents', () {
    TransactionModel make(TransactionType type) => TransactionModel()
      ..type = type
      ..amountCents = 6000;

    test('un ingreso suma', () {
      expect(make(TransactionType.income).signedCents, 6000);
    });

    test('un gasto resta', () {
      expect(make(TransactionType.expense).signedCents, -6000);
    });

    test('una transferencia resta de la cuenta origen', () {
      // El dinero sale de la cuenta propietaria; el destino lo suma aparte
      // en AccountRepository.balanceCents, dejando el balance total intacto.
      expect(make(TransactionType.transfer).signedCents, -6000);
    });
  });
}
