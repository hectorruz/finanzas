import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

import 'receipt_parser.dart';

export 'receipt_parser.dart' show ParsedReceipt;

/// Servicio de OCR on-device basado en Google ML Kit.
///
/// Reconoce el texto de la imagen y delega la interpretación en
/// [ReceiptParser], pasándole cada línea con su rectángulo para que pueda
/// reconstruir las filas físicas del ticket (ML Kit devuelve las columnas de
/// etiquetas e importes como bloques separados).
class OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final ReceiptParser _parser = ReceiptParser();

  Future<ParsedReceipt> processImage(String imagePath) async {
    if (!File(imagePath).existsSync()) {
      throw const FileSystemException('No se encontró la imagen del ticket.');
    }
    final List<OcrLine> lines;
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await _recognizer.processImage(input);
      lines = [
        for (final block in recognized.blocks)
          for (final line in block.lines) OcrLine(line.text, line.boundingBox),
      ];
    } catch (e) {
      throw Exception(
        'No se pudo reconocer el texto del ticket. Comprueba que el modelo de '
        'OCR está disponible y vuelve a intentarlo. ($e)',
      );
    }
    return _parser.parse(lines);
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
