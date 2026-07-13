/// Parser **puro** de una notificación de pago (Google Wallet u otra app de
/// pago) → importe en céntimos, comercio y fecha. Heurístico y testeable; no
/// depende de Isar ni de plugins. Devuelve `null` si la notificación no parece
/// un pago (sin importe reconocible).
library;

class ParsedWalletTxn {
  const ParsedWalletTxn({
    required this.cents,
    required this.merchant,
    required this.date,
  });

  /// Importe en céntimos, siempre > 0.
  final int cents;

  /// Comercio detectado (puede quedar vacío si no se reconoce).
  final String merchant;

  /// Fecha del pago (la de publicación de la notificación).
  final DateTime date;
}

/// Intenta interpretar una notificación como un pago. [title] y [text] son el
/// título y el cuerpo de la notificación; [postedAt], cuándo se publicó.
ParsedWalletTxn? parseWalletNotification({
  required String package,
  required String title,
  required String text,
  required DateTime postedAt,
}) {
  final haystack = '$title\n$text';
  final amountStr = _findAmountString(haystack);
  if (amountStr == null) return null;
  final cents = _toCents(amountStr);
  if (cents == null || cents <= 0) return null;
  final merchant = _extractMerchant(title: title, text: text) ?? '';
  return ParsedWalletTxn(cents: cents, merchant: merchant, date: postedAt);
}

/// Localiza la cadena del importe. Prioriza un número junto a un símbolo de
/// moneda (€/EUR/$/USD); si no, un número con dos decimales.
String? _findAmountString(String hay) {
  final withSymbol = RegExp(
    r'(?:€|eur|\$|usd)\s*([0-9][0-9.,]*[0-9]|[0-9])'
    r'|([0-9][0-9.,]*[0-9]|[0-9])\s*(?:€|eur|\$|usd)',
    caseSensitive: false,
  );
  final m = withSymbol.firstMatch(hay);
  if (m != null) return m.group(1) ?? m.group(2);
  final decimal = RegExp(r'[0-9][0-9.,]*[.,][0-9]{2}(?![0-9])');
  return decimal.firstMatch(hay)?.group(0);
}

/// Convierte un importe en texto a céntimos, tolerando formato europeo
/// (`1.234,56`) y anglosajón (`1,234.56`). El separador decimal es el `.` o `,`
/// seguido de exactamente dos dígitos al final; el resto son miles.
int? _toCents(String raw) {
  final t = raw.trim();
  final dec = RegExp(r'[.,](\d{2})$').firstMatch(t);
  String intPart;
  String centPart;
  if (dec != null) {
    centPart = dec.group(1)!;
    intPart = t.substring(0, dec.start);
  } else {
    intPart = t;
    centPart = '00';
  }
  intPart = intPart.replaceAll(RegExp(r'[^0-9]'), '');
  if (intPart.isEmpty) intPart = '0';
  final euros = int.tryParse(intPart);
  final cents = int.tryParse(centPart);
  if (euros == null || cents == null) return null;
  return euros * 100 + cents;
}

/// Nombres de notificación genéricos que **no** son un comercio.
const _genericTitles = {
  'google wallet',
  'google pay',
  'gpay',
  'wallet',
  'pago',
  'pago realizado',
  'payment',
};

/// Extrae el comercio: primero un patrón "en/at COMERCIO" en el cuerpo; si no,
/// el título cuando no es genérico.
String? _extractMerchant({required String title, required String text}) {
  final inMatch = RegExp(
    r'\b(?:en|at)\s+(.+?)(?:\s+(?:con|with|por|using|mediante|de)\b|[.,;:]|$)',
    caseSensitive: false,
  ).firstMatch(text);
  if (inMatch != null) {
    final cand = _clean(inMatch.group(1)!);
    if (cand.isNotEmpty) return cand;
  }
  final t = title.trim();
  if (t.isNotEmpty && !_genericTitles.contains(t.toLowerCase())) {
    return _clean(t);
  }
  return null;
}

String _clean(String s) => s
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[.,;:]+$'), '')
    .trim();
