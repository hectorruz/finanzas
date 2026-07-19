/// Cálculos puros de un depósito a plazo (sin Flutter ni Isar), para poder
/// testearlos aparte. Las TAE se manejan en **puntos básicos** (1 % = 100 bps)
/// y los importes en **céntimos enteros**, coherente con el resto de la app
/// (nunca `double` para dinero).
library;

/// Retención de IRPF sobre rendimientos del capital mobiliario aplicada a la
/// estimación de intereses de un depósito, en puntos básicos (19 % = tramo
/// estatal hasta 6.000 €; no se modelan los tramos superiores porque esto es
/// solo una estimación orientativa, no una liquidación fiscal).
const depositIrpfRateBps = 1900;

/// Interés bruto **simple** estimado de un depósito, sin redondear, en
/// céntimos (puede tener parte decimal).
///
/// `interés = capital · (bps / 10000) · (días / 365)`. Devuelve 0 si faltan
/// datos o si el rango de fechas no es positivo.
double _grossInterestCentsRaw({
  required int principalCents,
  required int? rateBps,
  required DateTime? start,
  required DateTime? end,
}) {
  if (rateBps == null || rateBps <= 0 || start == null || end == null) return 0;
  final days = end.difference(start).inDays;
  if (days <= 0 || principalCents <= 0) return 0;
  return principalCents * rateBps * days / (10000 * 365);
}

/// Interés bruto **simple** estimado de un depósito, en céntimos. El redondeo
/// al céntimo es explícito (`round`) y se aplica solo aquí, sobre el valor sin
/// redondear — nunca se encadena sobre un resultado ya redondeado, para no
/// perder precisión en los decimales.
int estimatedGrossInterestCents({
  required int principalCents,
  required int? rateBps,
  required DateTime? start,
  required DateTime? end,
}) {
  return _grossInterestCentsRaw(
    principalCents: principalCents,
    rateBps: rateBps,
    start: start,
    end: end,
  ).round();
}

/// Interés **neto** estimado tras retener el 19 % de IRPF, en céntimos.
///
/// Se calcula aplicando la retención sobre el interés bruto **sin redondear**
/// y redondeando solo el resultado final — no sobre
/// [estimatedGrossInterestCents], que ya viene redondeado al céntimo y
/// arrastraría un doble redondeo.
int estimatedNetInterestCents({
  required int principalCents,
  required int? rateBps,
  required DateTime? start,
  required DateTime? end,
}) {
  final grossRaw = _grossInterestCentsRaw(
    principalCents: principalCents,
    rateBps: rateBps,
    start: start,
    end: end,
  );
  return (grossRaw * (10000 - depositIrpfRateBps) / 10000).round();
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
