/// Regla **tarjeta → cuenta**: cuando el pago detectado se hizo con la tarjeta
/// [card], el gasto se imputa a la cuenta [accountId]. Dart puro; se serializa a
/// JSON para guardarse en `AppSettings.cardAccountRules`.
library;

import 'dart:convert';

class CardAccountRule {
  const CardAccountRule({required this.card, required this.accountId});

  /// Etiqueta de la tarjeta tal como se detecta/escribe (p. ej. `••1234`).
  final String card;

  /// Cuenta destino del gasto.
  final int accountId;

  /// Dígitos normalizados de la tarjeta (para casar de forma tolerante detección
  /// y regla aunque difieran los bullets/espacios).
  String get digits => card.replaceAll(RegExp(r'[^0-9]'), '');

  /// ¿Casa esta regla con la tarjeta [detected]? Compara por dígitos si los hay;
  /// si no, por texto normalizado.
  bool matches(String detected) {
    final d = detected.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty && d.isNotEmpty) return digits == d;
    return card.trim().toLowerCase() == detected.trim().toLowerCase();
  }

  Map<String, dynamic> toJson() => {'card': card, 'accountId': accountId};

  String encode() => jsonEncode(toJson());

  /// Decodifica una regla; `null` si el JSON es inválido o sin tarjeta.
  static CardAccountRule? tryDecode(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final card = (m['card'] as String? ?? '').trim();
      final accountId = (m['accountId'] as num?)?.toInt() ?? 0;
      if (card.isEmpty || accountId == 0) return null;
      return CardAccountRule(card: card, accountId: accountId);
    } catch (_) {
      return null;
    }
  }
}
