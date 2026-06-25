import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

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

/// Servicio de OCR on-device basado en Google ML Kit.
///
/// Reconoce el texto de la imagen del ticket y aplica heurísticas por Regex
/// para extraer el total, la fecha y el comercio, y sugerir una categoría.
class OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  Future<ParsedReceipt> processImage(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(input);
    final text = recognized.text;
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ParsedReceipt(
      rawText: text,
      merchant: _detectMerchant(lines),
      totalCents: _detectTotal(lines),
      date: _detectDate(text),
      suggestedCategory: _suggestCategory(text),
    );
  }

  /// El comercio suele estar en las primeras líneas (cabecera del ticket).
  String? _detectMerchant(List<String> lines) {
    for (final line in lines.take(4)) {
      final letters = line.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
      // Una cabecera plausible: suficientes letras y no es solo precios/fechas.
      if (letters.length >= 3 &&
          !RegExp(r'^\d').hasMatch(line) &&
          !line.toLowerCase().contains('factura') &&
          !line.toLowerCase().contains('ticket')) {
        return _titleCase(line);
      }
    }
    return lines.isNotEmpty ? _titleCase(lines.first) : null;
  }

  /// Busca la línea de total; si no hay etiqueta clara, toma el mayor importe.
  int? _detectTotal(List<String> lines) {
    final amountRe = RegExp(r'(\d{1,4}[.,]\d{2})');
    int? labelledTotal;
    int? maxAmount;

    for (final line in lines) {
      final lower = line.toLowerCase();
      final matches = amountRe.allMatches(line);
      for (final m in matches) {
        final cents = _toCents(m.group(1)!);
        if (cents == null) continue;
        if (cents > (maxAmount ?? -1)) maxAmount = cents;
        if (lower.contains('total') &&
            !lower.contains('subtotal') &&
            !lower.contains('iva')) {
          // La última coincidencia etiquetada como total suele ser el importe.
          labelledTotal = cents;
        }
      }
    }
    return labelledTotal ?? maxAmount;
  }

  DateTime? _detectDate(String text) {
    // Formatos comunes: dd/mm/yyyy, dd-mm-yyyy, dd.mm.yy
    final re = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})');
    final m = re.firstMatch(text);
    if (m == null) return null;
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(1)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  /// Sugerencia de categoría por palabras clave del ticket.
  String? _suggestCategory(String text) {
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

  int? _toCents(String raw) {
    final normalized = raw.replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) return null;
    return (value * 100).round();
  }

  String _titleCase(String input) {
    return input
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String? formatDate(DateTime? date) =>
      date == null ? null : DateFormat('d/M/yyyy').format(date);

  void dispose() => _recognizer.close();
}

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  ref.onDispose(service.dispose);
  return service;
});

