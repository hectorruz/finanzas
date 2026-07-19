/// Cálculos puros de un depósito a plazo (sin Flutter ni Isar), para poder
/// testearlos aparte. Las TAE se manejan en **puntos básicos** (1 % = 100 bps)
/// y los importes en **céntimos enteros**, coherente con el resto de la app
/// (nunca `double` para dinero).
library;

/// Interés bruto **simple** estimado de un depósito, en céntimos.
///
/// `interés = capital · (bps / 10000) · (días / 365)`. Devuelve 0 si faltan
/// datos o si el rango de fechas no es positivo. El redondeo al céntimo es
/// explícito (`round`).
int estimatedGrossInterestCents({
  required int principalCents,
  required int? rateBps,
  required DateTime? start,
  required DateTime? end,
}) {
  if (rateBps == null || rateBps <= 0 || start == null || end == null) return 0;
  final days = end.difference(start).inDays;
  if (days <= 0 || principalCents <= 0) return 0;
  final interest = principalCents * rateBps * days / (10000 * 365);
  return interest.round();
}

/// Formatea una TAE en puntos básicos como porcentaje español ("3,75 %").
/// Recorta los decimales finales innecesarios (350 → "3,5 %", 300 → "3 %").
String formatRateBps(int? rateBps) {
  if (rateBps == null) return '—';
  final pct = rateBps / 100; // bps → porcentaje
  var s = pct.toStringAsFixed(2);
  // Quita ceros finales y el punto si sobra.
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return '${s.replaceAll('.', ',')} %';
}

/// Días que faltan hasta el vencimiento contados desde [now] (por defecto, la
/// fecha actual). Negativo si ya venció; `null` si no hay fecha de vencimiento.
int? daysUntilMaturity(DateTime? end, {DateTime? now}) {
  if (end == null) return null;
  final ref = now ?? DateTime.now();
  return end.difference(ref).inDays;
}
