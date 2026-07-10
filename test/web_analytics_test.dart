import 'package:finanzas/data/models/enums.dart';
import 'package:finanzas/features/web/analytics/web_analytics.dart';
import 'package:finanzas/features/web/web_models.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionDto _tx(
  TransactionType type,
  int cents,
  DateTime date, {
  int? categoryId,
  int accountId = 1,
}) =>
    TransactionDto(
      type: type,
      amountCents: cents,
      concept: '',
      date: date,
      accountId: accountId,
      categoryId: categoryId,
    );

void main() {
  group('totalEffectCents', () {
    test('ingreso suma, gasto resta, transferencia neutra', () {
      expect(totalEffectCents(_tx(TransactionType.income, 100, DateTime(2026))),
          100);
      expect(totalEffectCents(_tx(TransactionType.expense, 100, DateTime(2026))),
          -100);
      expect(
          totalEffectCents(_tx(TransactionType.transfer, 100, DateTime(2026))),
          0);
    });
  });

  group('monthlyTotals', () {
    test('agrupa por mes y rellena huecos', () {
      final txns = [
        _tx(TransactionType.income, 1000, DateTime(2026, 3, 5)),
        _tx(TransactionType.expense, 400, DateTime(2026, 3, 20)),
        _tx(TransactionType.expense, 200, DateTime(2026, 1, 10)),
      ];
      final buckets = monthlyTotals(txns, months: 3, now: DateTime(2026, 3, 15));
      expect(buckets, hasLength(3));
      expect(buckets[0].month, DateTime(2026, 1));
      expect(buckets[0].expenseCents, 200);
      expect(buckets[1].incomeCents, 0); // febrero vacío
      expect(buckets[2].incomeCents, 1000);
      expect(buckets[2].expenseCents, 400);
      expect(buckets[2].netCents, 600);
    });
  });

  group('categoryBreakdown', () {
    test('agrupa por categoría raíz y ordena descendente', () {
      final cats = {
        1: CategoryDto(id: 1, name: 'Casa'),
        2: CategoryDto(id: 2, name: 'Luz', parentId: 1),
        3: CategoryDto(id: 3, name: 'Ocio'),
      };
      final txns = [
        _tx(TransactionType.expense, 300, DateTime(2026, 5, 1), categoryId: 2),
        _tx(TransactionType.expense, 100, DateTime(2026, 5, 2), categoryId: 1),
        _tx(TransactionType.expense, 500, DateTime(2026, 5, 3), categoryId: 3),
        _tx(TransactionType.expense, 50, DateTime(2026, 5, 4)), // sin categoría
      ];
      final slices = categoryBreakdown(txns, cats);
      expect(slices.first.categoryId, 3); // Ocio 500
      expect(slices.first.totalCents, 500);
      // Casa (raíz) suma la subcategoría Luz: 300 + 100 = 400
      final casa = slices.firstWhere((s) => s.categoryId == 1);
      expect(casa.totalCents, 400);
      final sinCat = slices.firstWhere((s) => s.categoryId == -1);
      expect(sinCat.label, 'Sin categoría');
    });

    test('respeta el rango de fechas', () {
      final txns = [
        _tx(TransactionType.expense, 100, DateTime(2026, 1, 1)),
        _tx(TransactionType.expense, 200, DateTime(2026, 5, 1)),
      ];
      final slices = categoryBreakdown(txns, const {},
          from: DateTime(2026, 4, 1), to: DateTime(2026, 6, 1));
      expect(slices, hasLength(1));
      expect(slices.single.totalCents, 200);
    });
  });

  group('balanceEvolution', () {
    test('reconstruye hacia atrás desde el saldo actual', () {
      final now = DateTime(2026, 5, 10);
      final txns = [
        _tx(TransactionType.expense, 500, DateTime(2026, 5, 10)),
      ];
      final points = balanceEvolution(txns,
          currentTotalCents: 1000, days: 3, now: now);
      expect(points, hasLength(3));
      // El último punto es el saldo actual.
      expect(points.last.balanceCents, 1000);
      // Antes del gasto de hoy había 1500.
      expect(points[1].balanceCents, 1500);
    });
  });

  group('periodSummary', () {
    test('suma ingresos/gastos y cuenta movimientos en el rango', () {
      final txns = [
        _tx(TransactionType.income, 1000, DateTime(2026, 5, 5)),
        _tx(TransactionType.expense, 400, DateTime(2026, 5, 6)),
        _tx(TransactionType.expense, 999, DateTime(2026, 1, 1)), // fuera
      ];
      final s = periodSummary(txns,
          from: DateTime(2026, 5, 1), to: DateTime(2026, 5, 31));
      expect(s.incomeCents, 1000);
      expect(s.expenseCents, 400);
      expect(s.count, 2);
      expect(s.netCents, 600);
    });
  });

  group('monthOverMonthChange', () {
    test('null si el periodo anterior fue 0', () {
      expect(monthOverMonthChange(100, 0), isNull);
      expect(monthOverMonthChange(150, 100), closeTo(0.5, 1e-9));
    });
  });
}
