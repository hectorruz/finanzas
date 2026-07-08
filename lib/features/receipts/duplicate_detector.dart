import '../../data/models/transaction.dart';

/// Busca en [candidates] un movimiento que parezca el **mismo apunte** que el
/// ticket escaneado: mismo importe, fecha a ±1 día y, si hay comercio, concepto
/// relacionado. Sirve para avisar antes de crear un doble apunte (p. ej. si el
/// gasto ya lo creó una regla recurrente o se anotó a mano).
///
/// Pura y sin Isar para poder testearla con listas en memoria.
TransactionModel? findPossibleDuplicate(
  List<TransactionModel> candidates, {
  required int cents,
  required DateTime date,
  required String merchant,
  int? excludeId,
}) {
  final normMerchant = _norm(merchant);
  final day = DateTime(date.year, date.month, date.day);

  for (final t in candidates) {
    if (excludeId != null && t.id == excludeId) continue;
    if (t.amountCents != cents) continue;

    final tDay = DateTime(t.date.year, t.date.month, t.date.day);
    if (tDay.difference(day).inDays.abs() > 1) continue;

    // Sin comercio detectado, importe+fecha ya es sospechoso de sobra.
    if (normMerchant.isEmpty) return t;

    final concept = _norm(t.concept);
    if (concept.isEmpty ||
        concept.contains(normMerchant) ||
        normMerchant.contains(concept)) {
      return t;
    }
  }
  return null;
}

String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
