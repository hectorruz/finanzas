import 'package:finanzas/data/models/transaction.dart';
import 'package:finanzas/features/receipts/duplicate_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Detección pura de posibles duplicados de un ticket contra movimientos.
void main() {
  TransactionModel tx(int id, int cents, DateTime date, String concept) =>
      TransactionModel()
        ..id = id
        ..amountCents = cents
        ..date = date
        ..concept = concept;

  final day = DateTime(2026, 6, 10);

  test('mismo importe, fecha y comercio → duplicado', () {
    final dup = findPossibleDuplicate(
      [tx(1, 4599, day, 'Mercadona')],
      cents: 4599,
      date: day,
      merchant: 'Mercadona',
    );
    expect(dup?.id, 1);
  });

  test('fecha a ±1 día también cuenta', () {
    final dup = findPossibleDuplicate(
      [tx(1, 4599, day.subtract(const Duration(days: 1)), 'Mercadona')],
      cents: 4599,
      date: day,
      merchant: 'mercadona',
    );
    expect(dup, isNotNull);
  });

  test('importe distinto o fecha lejana no es duplicado', () {
    final candidates = [
      tx(1, 4598, day, 'Mercadona'),
      tx(2, 4599, day.subtract(const Duration(days: 3)), 'Mercadona'),
    ];
    expect(
      findPossibleDuplicate(candidates,
          cents: 4599, date: day, merchant: 'Mercadona'),
      isNull,
    );
  });

  test('comercio sin relación no casa; sin comercio basta importe+fecha', () {
    final candidates = [tx(1, 4599, day, 'Gasolinera Repsol')];
    expect(
      findPossibleDuplicate(candidates,
          cents: 4599, date: day, merchant: 'Mercadona'),
      isNull,
    );
    expect(
      findPossibleDuplicate(candidates, cents: 4599, date: day, merchant: ''),
      isNotNull,
    );
  });

  test('excludeId ignora el movimiento ya vinculado al ticket', () {
    final dup = findPossibleDuplicate(
      [tx(5, 4599, day, 'Mercadona')],
      cents: 4599,
      date: day,
      merchant: 'Mercadona',
      excludeId: 5,
    );
    expect(dup, isNull);
  });
}
