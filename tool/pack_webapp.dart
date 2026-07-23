// Empaqueta el build de la webapp de escritorio en `assets/webapp.zip`, para
// que la app la sirva directamente desde el móvil (ver
// `lib/features/sync/net/webapp_assets.dart`).
//
// Uso, antes de compilar la APK de release:
//   flutter build web -t lib/main_web.dart
//   dart run tool/pack_webapp.dart
//
// Un zip de un solo fichero (no una carpeta) a propósito: `pubspec.yaml` no
// empaqueta directorios de forma recursiva, así que una carpeta se quedaría
// sin las subcarpetas del build web (assets/, canvaskit/, icons/, …).
import 'dart:io';

import 'package:archive/archive_io.dart';

Future<void> main() async {
  final buildWeb = Directory('build/web');
  if (!buildWeb.existsSync()) {
    stderr.writeln(
        'No existe build/web/. Ejecuta antes: flutter build web -t lib/main_web.dart');
    exitCode = 1;
    return;
  }

  const outputPath = 'assets/webapp.zip';

  // El propio zip declarado en pubspec acaba dentro del build web
  // (build/web/assets/assets/webapp.zip): si no se quita antes de empaquetar,
  // cada ciclo build+pack anida el zip del ciclo anterior y el fichero crece
  // como bola de nieve (llegó a 190 MB). La webapp nunca lo lee — solo lo
  // sirve el móvil — así que se elimina del build antes de comprimir.
  final nested = File('${buildWeb.path}/assets/assets/webapp.zip');
  if (nested.existsSync()) nested.deleteSync();

  final encoder = ZipFileEncoder();
  await encoder.zipDirectoryAsync(buildWeb, filename: outputPath);

  final size = await File(outputPath).length();
  stdout.writeln('Escrito $outputPath (${(size / 1024).round()} KiB).');
}
