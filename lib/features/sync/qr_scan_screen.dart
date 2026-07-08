import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'net/sync_qr.dart';

/// Escanea el QR que muestra el principal y devuelve el payload ya parseado
/// (`Navigator.pop`) o `null` si el usuario vuelve atrás sin escanear nada.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final parsed = parseSyncQrPayload(raw);
      if (parsed != null) {
        _handled = true;
        Navigator.of(context).pop(parsed);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
