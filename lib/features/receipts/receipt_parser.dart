import 'dart:ui' show Rect;

import '../../core/money/money.dart';

/// Línea de texto reconocida por OCR, con su rectángulo en la imagen si se
/// conoce. Sin rect (tests, texto plano) se respeta el orden de entrada.
class OcrLine {
  final String text;
  final Rect? box;

  const OcrLine(this.text, [this.box]);
}

/// Resultado del análisis heurístico de un ticket.
class ParsedReceipt {
  final String rawText;
  final String? merchant;
  final int? totalCents;
  final DateTime? date;
  final String? suggestedCategory;

  const ParsedReceipt({
    required this.rawText,
    this.merchant,
    this.totalCents,
    this.date,
    this.suggestedCategory,
  });
}

/// Heurísticas puras de interpretación de tickets, sin dependencia de ML Kit
/// para que `flutter test` pueda ejercitarlas.
///
/// El total se decide por puntuación de candidatos, no por exclusiones
/// binarias: cada importe hallado suma o resta según la etiqueta de su fila
/// (total / subtotal / efectivo / cambio…), su posición y si se repite.
class ReceiptParser {
  ParsedReceipt parse(List<OcrLine> lines) {
    final rows = reconstructRows(lines);
    final text = rows.join('\n');
    return ParsedReceipt(
      rawText: text,
      merchant: detectMerchant(rows),
      totalCents: detectTotalCents(rows),
      date: detectDate(text),
      suggestedCategory: suggestCategory(text),
    );
  }

  /// Reagrupa las líneas de OCR en filas físicas usando sus rectángulos.
  ///
  /// ML Kit devuelve los bloques en orden de detección, así que en tickets con
  /// importes alineados a la derecha la etiqueta ("TOTAL") y su número llegan
  /// separados. Aquí se reagrupan por solapamiento vertical: dos líneas están
  /// en la misma fila si sus centros distan menos de media altura de línea.
  static List<String> reconstructRows(List<OcrLine> lines) {
    final items = lines
        .map((l) => OcrLine(l.text.trim(), l.box))
        .where((l) => l.text.isNotEmpty)
        .toList();
    if (items.isEmpty) return const [];
    // Sin geometría fiable no se puede reordenar: se respeta el orden dado.
    if (items.any((l) => l.box == null || l.box!.height <= 0)) {
      return items.map((l) => l.text).toList();
    }

    final heights = items.map((l) => l.box!.height).toList()..sort();
    final lineHeight = heights[heights.length ~/ 2];

    final sorted = [...items]
      ..sort((a, b) => a.box!.center.dy.compareTo(b.box!.center.dy));

    final rows = <List<OcrLine>>[];
    var rowCenterSum = 0.0;
    for (final line in sorted) {
      final cy = line.box!.center.dy;
      if (rows.isNotEmpty) {
        final row = rows.last;
        // Media móvil del centro de la fila: tolera tickets algo inclinados.
        final rowCenter = rowCenterSum / row.length;
        if ((cy - rowCenter).abs() <= 0.5 * lineHeight) {
          row.add(line);
          rowCenterSum += cy;
          continue;
        }
      }
      rows.add([line]);
      rowCenterSum = cy;
    }

    for (final row in rows) {
      row.sort((a, b) => a.box!.left.compareTo(b.box!.left));
    }
    return [
      for (final row in rows) row.map((l) => l.text).join(' '),
    ];
  }

  // Importe monetario: 1-4 dígitos (con miles opcionales) + 2 decimales.
  // Los lookarounds evitan casar dentro de NIF/CIF/teléfonos ("37.722.103"),
  // porcentajes ("10.00%"), fechas ("04.07.26") y cantidades con unidad
  // ("8.30u"); se admite divisa pegada ("8,20EUR").
  static final RegExp _amountRe = RegExp(
    r'(?<!\d)(?<!\d[.,])(?:\d{1,3}(?:[. ]\d{3})+|\d{1,4})[.,]\d{2}'
    r'(?![\d%])(?![.,]\d)(?![a-df-zA-DF-Z])',
  );

  // Filas cuyo importe NO es el total (pagos, cambio, descuentos…).
  static final RegExp _negativeRe = RegExp(
    r'subtota+l|sub-tota+l|efectivo|metalico|metálico|cash|contant|entrega|'
    r'recib|cambio|change|terug|devoluc|vuelta|redondeo|propina|puntos|saldo|'
    r'ahorro|descuento|\bdto\b',
  );

  // Filas que anuncian el total (tota+l cubre "TOTAAL" y errores de OCR).
  static final RegExp _positiveRe = RegExp(
    r'tota+l|\bimporte\b|a pagar|te betalen|montant|amount',
  );

  // Pago con tarjeta: penalización suave, suele coincidir con el total.
  static final RegExp _cardRe = RegExp(
    r'tarjeta|\bcard\b|visa|mastercard|maestro|bancontact|credito|crédito|'
    r'debito|débito|datafono|datáfono',
  );

  // Desglose de impuestos: sus importes (base, cuota) nunca son el total.
  static final RegExp _vatWordRe =
      RegExp(r'\biva\b|i\.v\.a|\bvat\b|\bbtw\b|\btva\b|impuesto');
  static final RegExp _vatBreakdownRe =
      RegExp(r'base imponible|base imp|\bcuota\b|desglose');

  // Cabecera de columnas ("Cant. Descripcion P.U. Total"): su "total" no es
  // una etiqueta de total real.
  static final RegExp _headerRe = RegExp(
    r'articulo|artículo|descripc|\bcant\b|\bund\b|\buds\b|p\.u\.?|p/u|'
    r'precio|unidad',
  );

  /// Elige el total del ticket entre los importes de las filas dadas.
  static int? detectTotalCents(List<String> rows) {
    final infos = <_RowInfo>[];
    for (var i = 0; i < rows.length; i++) {
      infos.add(_RowInfo.analyze(rows[i], i));
    }

    final candidates = <_Candidate>[];

    // Candidatos directos: importes de filas no descartadas.
    for (final row in infos) {
      if (row.discarded) continue;
      for (var j = 0; j < row.amounts.length; j++) {
        var score = 0;
        if (row.negative) score -= 100;
        if (row.card) score -= 20;
        if (row.positive) {
          score += 100;
          // El importe más a la derecha de la fila del total suele ser él.
          if (j == row.amounts.length - 1) score += 10;
        }
        candidates.add(_Candidate(row.amounts[j], row.index, score));
      }
    }

    // Columnas separadas sin geometría: racha de filas solo-etiqueta seguida
    // de racha de filas solo-importe → emparejar posicionalmente.
    final adopted = <int>{};
    var i = 0;
    while (i < infos.length) {
      if (!infos[i].isLabelOnly) {
        i++;
        continue;
      }
      var j = i;
      while (j < infos.length && infos[j].isLabelOnly) {
        j++;
      }
      var k = j;
      while (k < infos.length && infos[k].isAmountOnly) {
        k++;
      }
      final labelCount = j - i;
      final amountCount = k - j;
      if (labelCount >= 2 &&
          amountCount >= 1 &&
          (labelCount - amountCount).abs() <= 1) {
        for (var p = 0; p < labelCount && p < amountCount; p++) {
          final label = infos[i + p];
          final source = infos[j + p];
          if (label.positive && !source.discarded && !source.negative) {
            candidates.add(_Candidate(source.amounts.last, label.index, 80));
            adopted.add(label.index);
          }
        }
      }
      i = k > j ? k : j;
    }

    // Vecindad: fila "total" sin importe → buscar una fila solo-importe
    // adyacente (columna partida que el emparejamiento no cubrió).
    for (final row in infos) {
      if (!row.positive || row.amounts.isNotEmpty || adopted.contains(row.index)) {
        continue;
      }
      for (final delta in const [1, -1, 2]) {
        final n = row.index + delta;
        if (n < 0 || n >= infos.length) continue;
        final other = infos[n];
        if (!other.isAmountOnly || other.discarded || other.negative) continue;
        candidates.add(_Candidate(other.amounts.last, row.index, 80));
        break;
      }
    }

    if (candidates.isEmpty) return null;

    // Bonus contextuales. Se mantienen por debajo de 80 para que un total
    // etiquetado nunca pierda contra un importe suelto.
    final rowsByCents = <int, Set<int>>{};
    for (final c in candidates) {
      rowsByCents.putIfAbsent(c.cents, () => <int>{}).add(c.rowIndex);
    }
    var maxCents = 0;
    for (final c in candidates) {
      if (c.score >= 0 && c.cents > maxCents) maxCents = c.cents;
    }
    for (final c in candidates) {
      if (rowsByCents[c.cents]!.length >= 2) c.score += 10;
      if (c.score >= 0 && c.cents == maxCents) c.score += 15;
      if (c.rowIndex >= infos.length / 2) c.score += 5;
    }

    _Candidate best = candidates.first;
    for (final c in candidates.skip(1)) {
      if (c.score > best.score ||
          (c.score == best.score && c.rowIndex > best.rowIndex) ||
          (c.score == best.score &&
              c.rowIndex == best.rowIndex &&
              c.cents > best.cents)) {
        best = c;
      }
    }
    return best.cents;
  }

  /// Importes válidos de una fila, en céntimos y en orden de aparición.
  static List<int> amountsIn(String text) {
    final amounts = <int>[];
    for (final m in _amountRe.allMatches(text)) {
      final cents = Money.parseToCents(m.group(0)!);
      if (cents != null && cents > 0) amounts.add(cents);
    }
    return amounts;
  }

  /// El comercio suele estar en las primeras líneas (cabecera del ticket).
  static String? detectMerchant(List<String> rows) {
    for (final row in rows.take(4)) {
      final letters = row.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
      // Una cabecera plausible: suficientes letras y no es solo precios/fechas.
      if (letters.length >= 3 &&
          !RegExp(r'^\d').hasMatch(row) &&
          !row.toLowerCase().contains('factura') &&
          !row.toLowerCase().contains('ticket')) {
        return _titleCase(row);
      }
    }
    return rows.isNotEmpty ? _titleCase(rows.first) : null;
  }

  static DateTime? detectDate(String text) {
    // Formatos comunes: dd/mm/yyyy, dd-mm-yyyy, dd.mm.yy. Se devuelve la
    // primera fecha plausible: un teléfono como "050/33.64.11" casa el patrón
    // pero no supera la validación y no debe cortar la búsqueda.
    final re = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})');
    for (final m in re.allMatches(text)) {
      var year = int.parse(m.group(3)!);
      if (year < 100) year += 2000;
      final month = int.parse(m.group(2)!);
      final day = int.parse(m.group(1)!);
      if (year < 1990 || year > 2100) continue;
      if (month < 1 || month > 12 || day < 1 || day > 31) continue;
      try {
        return DateTime(year, month, day);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Sugerencia de categoría por palabras clave del ticket.
  static String? suggestCategory(String text) {
    final t = text.toLowerCase();
    const rules = <String, List<String>>{
      'Alimentación': [
        'super', 'market', 'mercado', 'aliment', 'fruter', 'carnic',
        'panad', 'mercadona', 'carrefour', 'lidl', 'aldi', 'dia',
      ],
      'Transporte': [
        'gasolin', 'carburante', 'repsol', 'cepsa', 'bp', 'parking',
        'taxi', 'metro', 'renfe', 'peaje',
      ],
      'Salud': ['farmacia', 'parafarm', 'clinica', 'dental'],
      'Ocio': ['cine', 'restaurante', 'bar ', 'cafe', 'cerveceria', 'pizza'],
      'Compras': ['zara', 'decathlon', 'mediamarkt', 'amazon', 'ikea'],
    };
    for (final entry in rules.entries) {
      for (final kw in entry.value) {
        if (t.contains(kw)) return entry.key;
      }
    }
    return null;
  }

  static String _titleCase(String input) {
    return input
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _RowInfo {
  final int index;
  final List<int> amounts;
  final int letterCount;
  final bool negative;
  final bool positive;
  final bool card;
  final bool discarded;

  _RowInfo._({
    required this.index,
    required this.amounts,
    required this.letterCount,
    required this.negative,
    required this.positive,
    required this.card,
    required this.discarded,
  });

  factory _RowInfo.analyze(String text, int index) {
    final lower = text.toLowerCase();
    final amounts = ReceiptParser.amountsIn(text);
    final letterCount = text
        .replaceAll(ReceiptParser._amountRe, '')
        .replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '')
        .length;
    final negative = ReceiptParser._negativeRe.hasMatch(lower);
    final positive = !negative &&
        ReceiptParser._positiveRe.hasMatch(lower) &&
        !ReceiptParser._headerRe.hasMatch(lower);
    final discarded = ReceiptParser._vatBreakdownRe.hasMatch(lower) ||
        (lower.contains('%') &&
            ReceiptParser._vatWordRe.hasMatch(lower) &&
            !positive);
    return _RowInfo._(
      index: index,
      amounts: amounts,
      letterCount: letterCount,
      negative: negative,
      positive: positive,
      card: ReceiptParser._cardRe.hasMatch(lower),
      discarded: discarded,
    );
  }

  bool get isLabelOnly => amounts.isEmpty && letterCount >= 2;

  bool get isAmountOnly => amounts.isNotEmpty && letterCount <= 3;
}

class _Candidate {
  final int cents;
  final int rowIndex;
  int score;

  _Candidate(this.cents, this.rowIndex, this.score);
}
