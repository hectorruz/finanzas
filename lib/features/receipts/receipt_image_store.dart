import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Carpeta (dentro del almacenamiento de la app) donde se guardan de forma
/// persistente las fotos de los tickets. `image_picker` deja la imagen en una
/// caché temporal que el sistema puede limpiar; por eso copiamos el archivo a
/// esta carpeta propia y guardamos esa ruta estable en el `Receipt`.
const _receiptsDirName = 'receipts';

String _extension(String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  final dot = path.lastIndexOf('.');
  return (dot > slash && dot != -1) ? path.substring(dot) : '';
}

/// Copia [pickedPath] (ruta devuelta por `image_picker`) a
/// `<documentos>/receipts/` con un nombre único y devuelve la nueva ruta
/// persistente. Si algo falla, devuelve la ruta original como último recurso.
Future<String> persistReceiptImage(String pickedPath) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}$_receiptsDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final name =
        'receipt_${DateTime.now().millisecondsSinceEpoch}${_extension(pickedPath)}';
    final dest = '${dir.path}${Platform.pathSeparator}$name';
    await File(pickedPath).copy(dest);
    return dest;
  } catch (_) {
    return pickedPath;
  }
}

/// Guarda [bytes] (una foto subida desde la webapp de escritorio) en
/// `<documentos>/receipts/` con un nombre único y devuelve la ruta persistente.
/// La copia en `receipts/` es la fuente de verdad del móvil.
Future<String> persistReceiptImageBytes(List<int> bytes,
    {String extension = '.jpg'}) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir =
      Directory('${docs.path}${Platform.pathSeparator}$_receiptsDirName');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final name = 'receipt_${DateTime.now().millisecondsSinceEpoch}$extension';
  final dest = '${dir.path}${Platform.pathSeparator}$name';
  await File(dest).writeAsBytes(bytes);
  return dest;
}

/// Nombre del álbum de la galería del dispositivo donde se copian las fotos de
/// los tickets, para poder verlas desde la app de Galería/Fotos del móvil.
const receiptsGalleryAlbum = 'Finanzas';

/// Copia [imagePath] al álbum [receiptsGalleryAlbum] de la galería del
/// dispositivo. Es **mejor esfuerzo**: si no hay permiso o falla, devuelve
/// `false` sin lanzar, para no interrumpir el guardado del ticket (la copia
/// persistente de la app en `receipts/` sigue siendo la fuente de verdad).
Future<bool> saveReceiptToGallery(String imagePath) async {
  if (imagePath.isEmpty) return false;
  try {
    if (!await File(imagePath).exists()) return false;
    if (!await Gal.hasAccess(toAlbum: true)) {
      if (!await Gal.requestAccess(toAlbum: true)) return false;
    }
    await Gal.putImage(imagePath, album: receiptsGalleryAlbum);
    return true;
  } catch (_) {
    return false;
  }
}

/// Borra el archivo de imagen de un ticket, solo si vive dentro de la carpeta
/// `receipts/` gestionada por la app (best-effort: ignora errores y rutas
/// externas como las de la caché del picker de tickets antiguos).
Future<void> deleteReceiptImage(String imagePath) async {
  if (imagePath.isEmpty) return;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final managedDir =
        '${docs.path}${Platform.pathSeparator}$_receiptsDirName${Platform.pathSeparator}';
    if (!imagePath.startsWith(managedDir)) return;
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // best-effort
  }
}
