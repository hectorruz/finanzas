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
///
/// Los flags `*Confident` marcan la fiabilidad de cada campo para que la
/// pantalla de revisión resalte los de **baja confianza** antes de guardar:
/// nada se guarda a ciegas.
class ParsedReceipt {
  final String rawText;
  final String? merchant;
  final int? totalCents;
  final DateTime? date;
  final String? suggestedCategory;

  /// El comercio salió de una cabecera plausible (no del fallback).
  final bool merchantConfident;

  /// El total salió de una fila etiquetada ("TOTAL", "A PAGAR"…), no del
  /// fallback por puntuación (importe mayor / posición).
  final bool totalConfident;

  const ParsedReceipt({
    required this.rawText,
    this.merchant,
    this.totalCents,
    this.date,
    this.suggestedCategory,
    this.merchantConfident = false,
    this.totalConfident = false,
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
    final detailed = _detailedRows(lines);
    final rows = [for (final r in detailed) r.text];
    final text = rows.join('\n');
    final merchant = _detectMerchantFromRows(detailed);
    final total = detectTotal(rows);
    return ParsedReceipt(
      rawText: text,
      merchant: merchant.name,
      merchantConfident: merchant.confident,
      totalCents: total.cents,
      totalConfident: total.confident,
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
  static List<String> reconstructRows(List<OcrLine> lines) =>
      [for (final r in _detailedRows(lines)) r.text];

  /// Como [reconstructRows] pero conservando el rectángulo unión de cada fila
  /// física. La geometría (altura ≈ tamaño de fuente, posición) es la señal
  /// clave para detectar el comercio, así que no se descarta en este límite.
  static List<_Row> _detailedRows(List<OcrLine> lines) {
    final items = lines
        .map((l) => OcrLine(l.text.trim(), l.box))
        .where((l) => l.text.isNotEmpty)
        .toList();
    if (items.isEmpty) return const [];
    // Sin geometría fiable no se puede reordenar: se respeta el orden dado.
    if (items.any((l) => l.box == null || l.box!.height <= 0)) {
      return [for (final l in items) _Row(l.text, null)];
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

    final result = <_Row>[];
    for (final row in rows) {
      row.sort((a, b) => a.box!.left.compareTo(b.box!.left));
      var bounds = row.first.box!;
      for (final l in row.skip(1)) {
        bounds = bounds.expandToInclude(l.box!);
      }
      result.add(_Row(row.map((l) => l.text).join(' '), bounds));
    }
    return result;
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
  static int? detectTotalCents(List<String> rows) => detectTotal(rows).cents;

  /// Como [detectTotalCents], pero indicando además si el total salió de una
  /// fila etiquetada (confianza alta) o del fallback por puntuación.
  static ({int? cents, bool confident}) detectTotal(List<String> rows) {
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

    if (candidates.isEmpty) return (cents: null, confident: false);

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
    // >= 80: vino de una fila etiquetada o del emparejamiento de columnas; por
    // debajo es el fallback (importe mayor / posición), que conviene revisar.
    return (cents: best.cents, confident: best.score >= 80);
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

  /// Marcas conocidas: si una fila de cabecera contiene una de ellas, es el
  /// comercio con alta confianza aunque no sea la línea más grande. Se comparan
  /// como subcadena en minúsculas.
  static const List<String> knownMerchants = [
    // Supermercados
    'mercadona', 'carrefour', 'lidl', 'aldi', 'eroski', 'alcampo', 'consum',
    'hipercor', 'el corte ingles', 'ahorramas', 'ahorra mas', 'condis',
    'bonpreu', 'gadis', 'froiz', 'coviran', 'spar', 'caprabo', 'supersol',
    'masymas', 'mas y mas', 'dia %', 'supermercado dia', 'supeco',
    // Gasolineras
    'repsol', 'cepsa', 'shell', 'galp', 'ballenoil', 'petronor', 'plenoil',
    // Tiendas / grandes superficies
    'zara', 'decathlon', 'mediamarkt', 'media markt', 'amazon', 'ikea',
    'leroy merlin', 'bricomart', 'primark', 'pull&bear', 'bershka',
    'stradivarius', 'fnac', 'worten', 'pccomponentes', 'aki', 'bricodepot',
    // Restauración
    'mcdonald', 'burger king', 'kfc', 'telepizza', 'domino', 'starbucks',
    'vips', 'foster', 'goiko', 'taco bell', 'pans & company', 'pans and',
    // Salud / cosmética
    'farmacia', 'druni', 'primor', 'perfumeria',
  ];

  /// Ruido de cabecera que **no** es el nombre del comercio: direcciones, datos
  /// fiscales, teléfonos, webs, fechas/horas y frases de cortesía.
  static final RegExp _merchantNoiseRe = RegExp(
    r'\bc/|calle|avda|avenida|\bav\.|plaza|\bpza|paseo|\bctra|carretera|'
    r'pol[ií]gono|\bpol\.|\burb\b|local\b|planta\b|'
    r'\bcif\b|\bnif\b|c\.i\.f|n\.i\.f|\biva\b|factura|ticket|\bnum\b|'
    r'n[uú]mero|tel[eé]?f?[\s:o]|\btlf\b|www\.|http|@|\.com|\.es\b|'
    r'gracias|bienvenid|horario|abierto|'
    r'\d{1,2}[:h]\d{2}|\d{2}[/\-.]\d{2}[/\-.]\d{2,4}|\b\d{5}\b',
  );

  /// El comercio suele estar en las primeras líneas (cabecera del ticket).
  static String? detectMerchant(List<String> rows) => detectMerchantInfo(rows).name;

  /// Heurística **sin geometría** (para texto plano/tests): primera fila
  /// plausible de la cabecera; si ninguna lo es, la primera fila (baja
  /// confianza). La ruta con geometría (más precisa) es
  /// [_detectMerchantFromRows], que usa esta como respaldo.
  static ({String? name, bool confident}) detectMerchantInfo(List<String> rows) {
    for (final row in rows.take(4)) {
      final letters = row.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
      // Una cabecera plausible: suficientes letras y no es solo precios/fechas.
      if (letters.length >= 3 &&
          !RegExp(r'^\d').hasMatch(row) &&
          !row.toLowerCase().contains('factura') &&
          !row.toLowerCase().contains('ticket')) {
        return (name: _titleCase(row), confident: true);
      }
    }
    return (
      name: rows.isNotEmpty ? _titleCase(rows.first) : null,
      confident: false,
    );
  }

  /// Detecta el comercio puntuando las filas de **cabecera** con la geometría:
  /// el nombre de la tienda suele ser el texto **más grande y arriba**. Señales
  /// combinadas: tamaño de fuente (altura de caja frente a la mediana), posición
  /// vertical, proporción de letras, MAYÚSCULAS y diccionario de marcas; se
  /// descartan filas con importe, que empiezan por dígito o que son ruido de
  /// cabecera (dirección, CIF, teléfono, web, fecha…). Sin geometría delega en
  /// [detectMerchantInfo].
  static ({String? name, bool confident}) _detectMerchantFromRows(
      List<_Row> rows) {
    if (rows.isEmpty) return (name: null, confident: false);
    final hasGeometry = rows.any((r) => r.bounds != null);
    if (!hasGeometry) {
      return detectMerchantInfo([for (final r in rows) r.text]);
    }

    final hs = [for (final r in rows) if (r.bounds != null) r.bounds!.height]
      ..sort();
    final medianHeight = hs.isEmpty ? 1.0 : hs[hs.length ~/ 2];

    final headerCount = rows.length < 8 ? rows.length : 8;
    _MerchantCand? best;
    for (var i = 0; i < headerCount; i++) {
      final text = rows[i].text;
      final lower = text.toLowerCase();
      // Exclusiones duras: cabeceras no llevan precios ni empiezan por dígito
      // (direcciones, códigos postales), y descartamos el ruido conocido.
      if (amountsIn(text).isNotEmpty) continue;
      if (RegExp(r'^\s*\d').hasMatch(text)) continue;
      if (_merchantNoiseRe.hasMatch(lower)) continue;
      final letters = text.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
      if (letters.length < 3) continue;

      final bounds = rows[i].bounds;
      final ratio = bounds != null ? bounds.height / medianHeight : 1.0;
      final compact = text.replaceAll(RegExp(r'\s'), '');
      final letterRatio = compact.isEmpty ? 0.0 : letters.length / compact.length;
      final brand = knownMerchants.any(lower.contains);

      var score = (ratio - 1.0) * 40; // tamaño de fuente (señal principal)
      score += (headerCount - i) * 3; // más arriba, mejor
      if (letterRatio >= 0.6) score += 15;
      if (letters.length >= 3 && letters == letters.toUpperCase()) score += 8;
      if (brand) score += 1000; // marca conocida: decisivo

      if (best == null || score > best.score) {
        best = _MerchantCand(text, score, ratio, brand);
      }
    }

    if (best == null) {
      // Ninguna cabecera plausible: respaldo a la primera fila, baja confianza.
      return (name: _titleCase(rows.first.text), confident: false);
    }
    // Confianza alta si es una marca conocida o destaca claramente por tamaño.
    final confident = best.brand || best.heightRatio >= 1.25;
    return (name: _cleanMerchant(best.text), confident: confident);
  }

  /// Limpia el nombre del comercio para mostrarlo (y para que el mismo comercio
  /// produzca la misma cadena entre escaneos, mejorando la memoria
  /// comercio→categoría): quita símbolos de OCR y colapsa espacios.
  static String _cleanMerchant(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[*#|_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _titleCase(cleaned);
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

/// Fila física reconstruida con su rectángulo unión (null sin geometría).
class _Row {
  final String text;
  final Rect? bounds;
  const _Row(this.text, this.bounds);
}

/// Candidato a comercio con su puntuación y las señales que deciden la
/// confianza (marca conocida / tamaño de fuente relativo).
class _MerchantCand {
  final String text;
  final double score;
  final double heightRatio;
  final bool brand;

  _MerchantCand(this.text, this.score, this.heightRatio, this.brand);
}
