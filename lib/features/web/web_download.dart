import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Dispara la descarga de [bytes] como un fichero en el navegador (crea un Blob
/// y hace click en un enlace temporal). Solo tiene sentido en el target web.
void webDownloadBytes(Uint8List bytes, String filename, String mime) {
  final parts = [bytes.toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
