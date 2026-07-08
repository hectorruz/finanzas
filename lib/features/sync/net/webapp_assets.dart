import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Extrae el build de la webapp de escritorio (empaquetado como fichero único
/// `assets/webapp.zip`, ver `tool/pack_webapp.dart`) a un directorio real en
/// disco, para que `LanSyncServer` lo sirva como `webRoot`: su `_serveStatic`
/// usa `dart:io File`, así que no puede leer directamente del asset bundle de
/// Flutter (y una carpeta declarada en `pubspec.yaml` no se empaqueta de forma
/// recursiva — por eso va como zip de un solo fichero, no como carpeta).
class WebappAssets {
  const WebappAssets._();

  static const _assetKey = 'assets/webapp.zip';
  static const _subdir = 'webapp';
  static const _markerFile = '.size';

  /// Extrae (si hace falta) y devuelve el directorio con la webapp lista para
  /// servir, o `null` si el asset no se pudo cargar/decodificar. Nunca lanza:
  /// un problema aquí no debe impedir que arranque el servidor de sync.
  static Future<String?> ensureExtracted() async {
    try {
      final byteData = await rootBundle.load(_assetKey);
      final bytes = byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

      final base = await getApplicationSupportDirectory();
      final outDir = Directory('${base.path}/$_subdir');
      final marker = File('${outDir.path}/$_markerFile');

      // Marca barata (tamaño en bytes del zip) para no reextraer en cada
      // arranque del servidor si el asset no ha cambiado.
      if (await marker.exists() &&
          await marker.readAsString() == '${bytes.length}') {
        return outDir.path;
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      await extractArchiveToDisk(archive, outDir.path);
      await marker.writeAsString('${bytes.length}');
      return outDir.path;
    } catch (_) {
      return null;
    }
  }
}
