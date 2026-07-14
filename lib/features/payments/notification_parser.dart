/// Parser **puro** de una notificación de pago (Google Wallet u otra app de
/// pago configurada) → importe en céntimos, comercio, tarjeta y fecha.
/// Heurístico y testeable; no depende de Isar ni de plugins.
///
/// Cada app puede tener su propia [NotificationRule] que dice *dónde buscar*
/// cada dato (regex por campo). Google Wallet es una regla built-in implícita
/// (`NotificationRule.wallet`): tienda en el título, importe y tarjeta con las
/// heurísticas genéricas. Devuelve `null` cuando no se reconoce un importe.
library;

import 'dart:convert';

/// Resultado del parseo de una notificación de pago.
class ParsedPayment {
  const ParsedPayment({
    required this.cents,
    required this.merchant,
    required this.card,
    required this.date,
  });

  /// Importe en céntimos, siempre > 0.
  final int cents;

  /// Comercio detectado (vacío si no se reconoce).
  final String merchant;

  /// Tarjeta detectada, p. ej. `••1234` (vacío si no se reconoce).
  final String card;

  /// Fecha del pago (la de publicación de la notificación).
  final DateTime date;
}

/// Regla de lectura de una app: qué paquete y *dónde buscar* importe/tienda/
/// tarjeta. Los campos regex son opcionales; si faltan se usan las heurísticas
/// genéricas. Se serializa a JSON para guardarse en `AppSettings`.
class NotificationRule {
  const NotificationRule({
    required this.package,
    required this.label,
    this.merchantFromTitle = false,
    this.merchantRegex,
    this.amountRegex,
    this.cardRegex,
  });

  /// Paquete de la app (p. ej. `com.google.android.apps.walletnfcrel`).
  final String package;

  /// Nombre legible para la UI.
  final String label;

  /// Si el comercio es el **título** de la notificación (cuando no es genérico).
  /// Si además no casa nada, se usa la heurística "en/at X".
  final bool merchantFromTitle;

  /// Regex para el comercio; si tiene grupo 1 se usa, si no, la coincidencia
  /// completa. Tiene prioridad sobre [merchantFromTitle].
  final String? merchantRegex;

  /// Regex para el importe; grupo 1 (o coincidencia completa). Si falta, se usa
  /// el buscador genérico de dinero.
  final String? amountRegex;

  /// Regex para la tarjeta; grupo 1 (o coincidencia completa). Si falta, se usa
  /// la heurística genérica de tarjeta.
  final String? cardRegex;

  /// Paquete de Google Wallet.
  static const walletPackage = 'com.google.android.apps.walletnfcrel';

  /// Regla built-in de Google Wallet (implícita, no se guarda en ajustes).
  factory NotificationRule.wallet() => const NotificationRule(
        package: walletPackage,
        label: 'Google Wallet',
        merchantFromTitle: true,
      );

  NotificationRule copyWith({
    String? package,
    String? label,
    bool? merchantFromTitle,
    String? merchantRegex,
    String? amountRegex,
    String? cardRegex,
  }) =>
      NotificationRule(
        package: package ?? this.package,
        label: label ?? this.label,
        merchantFromTitle: merchantFromTitle ?? this.merchantFromTitle,
        merchantRegex: merchantRegex ?? this.merchantRegex,
        amountRegex: amountRegex ?? this.amountRegex,
        cardRegex: cardRegex ?? this.cardRegex,
      );

  Map<String, dynamic> toJson() => {
        'package': package,
        'label': label,
        'merchantFromTitle': merchantFromTitle,
        if (_has(merchantRegex)) 'merchantRegex': merchantRegex,
        if (_has(amountRegex)) 'amountRegex': amountRegex,
        if (_has(cardRegex)) 'cardRegex': cardRegex,
      };

  String encode() => jsonEncode(toJson());

  /// Decodifica una regla; devuelve `null` si el JSON es inválido o sin paquete.
  static NotificationRule? tryDecode(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final package = (m['package'] as String? ?? '').trim();
      if (package.isEmpty) return null;
      return NotificationRule(
        package: package,
        label: (m['label'] as String? ?? '').trim(),
        merchantFromTitle: m['merchantFromTitle'] as bool? ?? false,
        merchantRegex: _clean(m['merchantRegex'] as String?),
        amountRegex: _clean(m['amountRegex'] as String?),
        cardRegex: _clean(m['cardRegex'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _has(String? s) => s != null && s.isNotEmpty;
  static String? _clean(String? s) => (s == null || s.isEmpty) ? null : s;
}

/// Elige la regla que corresponde a [package] (la de la lista o, para el
/// paquete de Wallet / cualquier otro sin regla, la built-in de Wallet) y la
/// aplica. Es el punto de entrada que usa la ingesta.
ParsedPayment? parseWithRules({
  required String package,
  required String title,
  required String text,
  required DateTime postedAt,
  required List<NotificationRule> rules,
}) {
  NotificationRule? rule;
  for (final r in rules) {
    if (r.package == package) {
      rule = r;
      break;
    }
  }
  // Sin regla explícita: se usa la semántica de Wallet (comercio en título +
  // heurísticas genéricas), que sirve como fallback razonable.
  rule ??= NotificationRule.wallet();
  return applyRule(rule, title: title, text: text, postedAt: postedAt);
}

/// Aplica una [rule] concreta a una notificación. `null` si no hay importe.
ParsedPayment? applyRule(
  NotificationRule rule, {
  required String title,
  required String text,
  required DateTime postedAt,
}) {
  final haystack = '$title\n$text';
  final cents = _resolveCents(rule, haystack);
  if (cents == null || cents <= 0) return null;
  return ParsedPayment(
    cents: cents,
    merchant: _resolveMerchant(rule, title, text, haystack),
    card: _resolveCard(rule, haystack),
    date: postedAt,
  );
}

// --- Importe ---

int? _resolveCents(NotificationRule rule, String haystack) {
  final re = _compile(rule.amountRegex);
  if (re != null) {
    final m = re.firstMatch(haystack);
    if (m == null) return null; // regex explícita que no casa → no es un pago
    final raw = (m.groupCount >= 1 ? m.group(1) : null) ?? m.group(0);
    if (raw == null) return null;
    return _toCents(_findAmountString(raw) ?? raw);
  }
  final str = _findAmountString(haystack);
  return str == null ? null : _toCents(str);
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
/// (`1.234,56`) y anglosajón (`1,234.56`). El separador decimal es `.` o `,`
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

// --- Comercio ---

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

String _resolveMerchant(
    NotificationRule rule, String title, String text, String haystack) {
  final re = _compile(rule.merchantRegex);
  if (re != null) {
    final m = re.firstMatch(haystack);
    if (m == null) return '';
    return _clean((m.groupCount >= 1 ? m.group(1) : null) ?? m.group(0) ?? '');
  }
  if (rule.merchantFromTitle) {
    final t = _clean(title);
    if (t.isNotEmpty && !_genericTitles.contains(t.toLowerCase())) return t;
  }
  return _merchantHeuristic(title, text);
}

/// Comercio por heurística: un patrón "en/at COMERCIO" en el cuerpo; si no, el
/// título cuando no es genérico.
String _merchantHeuristic(String title, String text) {
  final inMatch = RegExp(
    r'\b(?:en|at)\s+(.+?)(?:\s+(?:con|with|por|using|mediante|de)\b|[.,;:]|$)',
    caseSensitive: false,
  ).firstMatch(text);
  if (inMatch != null) {
    final cand = _clean(inMatch.group(1)!);
    if (cand.isNotEmpty) return cand;
  }
  final t = _clean(title);
  if (t.isNotEmpty && !_genericTitles.contains(t.toLowerCase())) return t;
  return '';
}

// --- Tarjeta ---

String _resolveCard(NotificationRule rule, String haystack) {
  final re = _compile(rule.cardRegex);
  if (re != null) {
    final m = re.firstMatch(haystack);
    if (m == null) return '';
    return _clean((m.groupCount >= 1 ? m.group(1) : null) ?? m.group(0) ?? '');
  }
  return _cardHeuristic(haystack);
}

/// Tarjeta por heurística: bloque de bullets/asteriscos seguido de dígitos
/// (`••1234`) o una palabra clave de tarjeta seguida de los últimos dígitos.
/// Devuelve `••NNNN` normalizado, o vacío.
String _cardHeuristic(String hay) {
  final m = RegExp(
    r'(?:[•·*∙・]\s*){1,}\s*(\d{2,4})'
    r'|(?:tarjeta|card|terminada\s+en|ending(?:\s+in)?)\s*[•·*∙・:]*\s*(\d{2,4})',
    caseSensitive: false,
  ).firstMatch(hay);
  if (m == null) return '';
  final digits = m.group(1) ?? m.group(2);
  return digits == null ? '' : '••$digits';
}

// --- Utilidades ---

/// Compila una regex de usuario; `null` si está vacía o es inválida (para
/// degradar a la heurística en vez de lanzar por un patrón mal escrito).
RegExp? _compile(String? pattern) {
  if (pattern == null || pattern.trim().isEmpty) return null;
  try {
    return RegExp(pattern, caseSensitive: false);
  } on FormatException {
    return null;
  }
}

String _clean(String s) => s
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[.,;:]+$'), '')
    .trim();
