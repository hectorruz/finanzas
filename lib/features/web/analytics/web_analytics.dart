import '../../../data/models/enums.dart';
import '../web_models.dart';

/// Analítica **pura** de la webapp: recalcula agregados en el navegador a partir
/// de los movimientos/cuentas/categorías ya descargados, sin round-trips ni
/// dependencias de Flutter/Isar (así es testeable y reutilizable).

/// Ingresos y gastos de un mes concreto.
class MonthBucket {
  const MonthBucket({
    required this.month,
    required this.incomeCents,
    required this.expenseCents,
  });

  /// Primer día del mes.
  final DateTime month;
  final int incomeCents;
  final int expenseCents;

  int get netCents => incomeCents - expenseCents;
}

/// Porción de un reparto por categoría (para el donut).
class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.label,
    required this.colorValue,
    required this.totalCents,
  });

  /// Id de la categoría raíz, o -1 para "Sin categoría".
  final int categoryId;
  final String label;
  final int colorValue;
  final int totalCents;
}

/// Punto de la evolución del balance total.
class BalancePoint {
  const BalancePoint(this.date, this.balanceCents);
  final DateTime date;
  final int balanceCents;
}

/// Efecto de un movimiento sobre el **balance total** (la suma de todas las
/// cuentas propias): un ingreso suma, un gasto resta, una transferencia no
/// cambia el total (mueve dinero entre cuentas propias).
int totalEffectCents(TransactionDto t) {
  switch (t.type) {
    case TransactionType.income:
      return t.amountCents;
    case TransactionType.expense:
      return -t.amountCents;
    case TransactionType.transfer:
      return 0;
  }
}

DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  return DateTime(d.year + (total ~/ 12), (total % 12) + 1);
}

/// Ingresos/gastos agrupados por mes, para los últimos [months] meses acabando
/// en el mes de [now] (incluido). Rellena con ceros los meses sin movimientos.
List<MonthBucket> monthlyTotals(
  List<TransactionDto> txns, {
  int months = 6,
  DateTime? now,
}) {
  final end = _firstOfMonth(now ?? DateTime.now());
  final start = _addMonths(end, -(months - 1));
  final income = <DateTime, int>{};
  final expense = <DateTime, int>{};
  for (final t in txns) {
    final m = _firstOfMonth(t.date);
    if (m.isBefore(start) || m.isAfter(end)) continue;
    if (t.type == TransactionType.income) {
      income[m] = (income[m] ?? 0) + t.amountCents;
    } else if (t.type == TransactionType.expense) {
      expense[m] = (expense[m] ?? 0) + t.amountCents;
    }
  }
  return [
    for (var i = 0; i < months; i++)
      () {
        final m = _addMonths(start, i);
        return MonthBucket(
          month: m,
          incomeCents: income[m] ?? 0,
          expenseCents: expense[m] ?? 0,
        );
      }(),
  ];
}

/// Ingresos/gastos por mes entre `[from, to]` (ambos inclusive por mes),
/// rellenando los meses intermedios sin movimientos.
List<MonthBucket> monthlyTotalsBetween(
  List<TransactionDto> txns, {
  required DateTime from,
  required DateTime to,
}) {
  final start = _firstOfMonth(from);
  final end = _firstOfMonth(to);
  var months = (end.year - start.year) * 12 + (end.month - start.month) + 1;
  if (months < 1) months = 1;
  if (months > 60) months = 60; // tope de seguridad
  final income = <DateTime, int>{};
  final expense = <DateTime, int>{};
  for (final t in txns) {
    final m = _firstOfMonth(t.date);
    if (m.isBefore(start) || m.isAfter(end)) continue;
    if (t.type == TransactionType.income) {
      income[m] = (income[m] ?? 0) + t.amountCents;
    } else if (t.type == TransactionType.expense) {
      expense[m] = (expense[m] ?? 0) + t.amountCents;
    }
  }
  return [
    for (var i = 0; i < months; i++)
      () {
        final m = _addMonths(start, i);
        return MonthBucket(
          month: m,
          incomeCents: income[m] ?? 0,
          expenseCents: expense[m] ?? 0,
        );
      }(),
  ];
}

/// Resumen de un periodo: ingresos, gastos y nº de movimientos.
class PeriodSummary {
  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.count,
  });
  final int incomeCents;
  final int expenseCents;
  final int count;
  int get netCents => incomeCents - expenseCents;
}

/// Totales de un periodo `[from, to)` (to exclusivo al final del día ya lo
/// aplica el llamador si quiere; aquí es simplemente `!isAfter`).
PeriodSummary periodSummary(
  List<TransactionDto> txns, {
  required DateTime from,
  required DateTime to,
}) {
  var income = 0, expense = 0, count = 0;
  for (final t in txns) {
    if (t.date.isBefore(from) || t.date.isAfter(to)) continue;
    count++;
    if (t.type == TransactionType.income) income += t.amountCents;
    if (t.type == TransactionType.expense) expense += t.amountCents;
  }
  return PeriodSummary(incomeCents: income, expenseCents: expense, count: count);
}

/// Id de la categoría raíz (subiendo por `parentId`), o el propio id si no tiene
/// padre válido en el mapa.
int rootCategoryId(int id, Map<int, CategoryDto> byId) {
  var current = byId[id];
  final seen = <int>{};
  while (current != null &&
      current.parentId != null &&
      byId[current.parentId] != null &&
      seen.add(current.id)) {
    current = byId[current.parentId];
  }
  return current?.id ?? id;
}

/// Reparto por **categoría raíz** de los movimientos de un [type] dentro del
/// rango [from, to] (ambos opcionales), ordenado de mayor a menor. Los
/// movimientos sin categoría se agrupan en una porción "Sin categoría" (id -1).
List<CategorySlice> categoryBreakdown(
  List<TransactionDto> txns,
  Map<int, CategoryDto> categoriesById, {
  TransactionType type = TransactionType.expense,
  DateTime? from,
  DateTime? to,
}) {
  final totals = <int, int>{};
  for (final t in txns) {
    if (t.type != type) continue;
    if (from != null && t.date.isBefore(from)) continue;
    if (to != null && !t.date.isBefore(to)) continue;
    final root = t.categoryId == null
        ? -1
        : rootCategoryId(t.categoryId!, categoriesById);
    totals[root] = (totals[root] ?? 0) + t.amountCents;
  }
  final slices = totals.entries.map((e) {
    final cat = e.key == -1 ? null : categoriesById[e.key];
    return CategorySlice(
      categoryId: e.key,
      label: cat?.name ?? 'Sin categoría',
      colorValue: cat?.colorValue ?? 0xFF9E9E9E,
      totalCents: e.value,
    );
  }).toList()
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return slices;
}

/// Evolución del **balance total** hacia atrás desde [currentTotalCents] (el
/// saldo de hoy) restando el efecto de los movimientos, produciendo un punto por
/// día para los últimos [days] días. El último punto es el saldo actual.
List<BalancePoint> balanceEvolution(
  List<TransactionDto> txns, {
  required int currentTotalCents,
  int days = 90,
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final start = today.subtract(Duration(days: days - 1));

  // Efecto por día dentro de la ventana.
  final effectByDay = <DateTime, int>{};
  // Efecto total posterior a cada día lo obtenemos recorriendo hacia atrás.
  for (final t in txns) {
    final d = _dateOnly(t.date);
    if (d.isBefore(start) || d.isAfter(today)) continue;
    effectByDay[d] = (effectByDay[d] ?? 0) + totalEffectCents(t);
  }

  // Reconstruye hacia atrás: balance al cierre de cada día.
  final points = <BalancePoint>[];
  var running = currentTotalCents;
  for (var d = today; !d.isBefore(start); d = d.subtract(const Duration(days: 1))) {
    points.add(BalancePoint(d, running));
    running -= effectByDay[d] ?? 0; // deshace el día para llegar al día anterior
  }
  return points.reversed.toList();
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Variación porcentual de gasto de este mes respecto al anterior (útil para el
/// KPI "vs. mes anterior"). Devuelve `null` si el mes anterior fue 0.
double? monthOverMonthChange(int thisMonthCents, int lastMonthCents) {
  if (lastMonthCents == 0) return null;
  return (thisMonthCents - lastMonthCents) / lastMonthCents;
}
