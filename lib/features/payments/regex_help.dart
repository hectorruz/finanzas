/// Ayuda para escribir las reglas de lectura: validación de patrones y un
/// recetario de los casos habituales. Dart puro (sin Flutter) para poder
/// testearlo; la pantalla que lo pinta es `payment_rules_help_screen.dart`.
library;

/// Campo de la regla al que aplica una receta.
enum RegexField { merchant, amount, card }

/// Comprueba si [pattern] es un regex válido. Devuelve `null` si lo es (o si
/// está vacío, que significa "detección automática") y si no, el motivo.
///
/// El parser degrada un patrón inválido a la heurística automática en silencio
/// (`_compile` en `notification_parser.dart` se traga la `FormatException`), así
/// que sin esto un paréntesis sin cerrar es indistinguible de dejar el campo
/// vacío: parece que funciona, pero la regla no se está usando.
String? regexError(String pattern) {
  if (pattern.trim().isEmpty) return null;
  try {
    RegExp(pattern);
    return null;
  } on FormatException catch (e) {
    return 'No es un patrón válido: ${e.message}';
  }
}

/// Un patrón listo para copiar, con el texto de ejemplo que sabe leer.
class RegexRecipe {
  const RegexRecipe({
    required this.field,
    required this.title,
    required this.pattern,
    required this.example,
    required this.extracts,
  });

  /// A qué campo de la regla se pega.
  final RegexField field;

  /// Qué caso resuelve, en cristiano.
  final String title;

  /// El patrón en sí.
  final String pattern;

  /// Notificación de ejemplo sobre la que casa.
  final String example;

  /// Lo que saca de [example]. El test comprueba que sea verdad.
  final String extracts;
}

/// Recetario: los patrones que cubren la mayoría de las apps de pago españolas.
const List<RegexRecipe> kRegexRecipes = [
  RegexRecipe(
    field: RegexField.amount,
    title: 'Importe con el símbolo €',
    pattern: r'([0-9]+[.,][0-9]{2})\s*€',
    example: 'Has pagado 23,45 € en MERCADONA',
    extracts: '23,45',
  ),
  RegexRecipe(
    field: RegexField.amount,
    title: 'Importe con EUR',
    pattern: r'([0-9]+[.,][0-9]{2})\s*EUR',
    example: 'Compra de 12.30 EUR',
    extracts: '12.30',
  ),
  RegexRecipe(
    field: RegexField.amount,
    title: 'Importe tras "importe" o "por"',
    pattern: r'(?:importe|por)\s*:?\s*([0-9]+[.,][0-9]{2})',
    example: 'Cargo en cuenta. Importe: 8,90',
    extracts: '8,90',
  ),
  RegexRecipe(
    field: RegexField.merchant,
    title: 'Tienda después de "en"',
    pattern: r'\ben\s+(.+?)(?:\s+con\b|[.,]|$)',
    example: 'Pago de 23,45 € en MERCADONA con tarjeta',
    extracts: 'MERCADONA',
  ),
  RegexRecipe(
    field: RegexField.merchant,
    title: 'Tienda entre "Compra en …" y "por"',
    pattern: r'Compra en (.+?) por',
    example: 'Compra en LIDL por 15,00 €',
    extracts: 'LIDL',
  ),
  RegexRecipe(
    field: RegexField.merchant,
    title: 'Tienda entre comillas',
    pattern: r'"(.+?)"',
    example: 'Pago aceptado en "Bar Pepe"',
    extracts: 'Bar Pepe',
  ),
  RegexRecipe(
    field: RegexField.card,
    title: 'Tarjeta con puntos o asteriscos',
    pattern: r'(?:\*{2,}|•{2,}|x{4})\s*(\d{4})',
    example: 'Tarjeta ••1234',
    extracts: '1234',
  ),
  RegexRecipe(
    field: RegexField.card,
    title: 'Tarjeta después de la palabra "tarjeta"',
    pattern: r'tarjeta\s+\S*\s*(\d{4})',
    example: 'Pagado con tarjeta Visa 5678',
    extracts: '5678',
  ),
];

/// Los símbolos que hacen falta para leer el recetario.
const List<({String token, String meaning})> kRegexGlossary = [
  (token: r'(…)', meaning: 'Grupo: lo que va aquí dentro es el valor que se extrae'),
  (token: r'(?:…)', meaning: 'Agrupa sin extraer (para usarlo con | )'),
  (token: r'.', meaning: 'Un carácter cualquiera'),
  (token: r'+', meaning: 'Uno o más del anterior'),
  (token: r'*', meaning: 'Cero o más del anterior'),
  (token: r'?', meaning: 'Tras + o *, coge lo mínimo posible en vez de lo máximo'),
  (token: r'\d', meaning: 'Un dígito (0-9)'),
  (token: r'\s', meaning: 'Un espacio'),
  (token: r'\S', meaning: 'Cualquier cosa que no sea un espacio'),
  (token: r'{4}', meaning: 'Exactamente 4 del anterior'),
  (token: r'|', meaning: 'O una cosa, o la otra'),
  (token: r'\b', meaning: 'Borde de palabra: \ben solo casa la palabra "en" suelta'),
  (token: r'$', meaning: 'Fin del texto'),
];
