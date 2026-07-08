import 'dart:io';

import 'package:finanzas/features/sync/net/webapp_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Extracción del build de la webapp (empaquetado en `assets/webapp.zip`, ver
/// `tool/pack_webapp.dart`) a un directorio real para `LanSyncServer.webRoot`.
/// De paso comprueba que el zip placeholder committeado es válido.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._dir);
  final Directory _dir;

  @override
  Future<String?> getApplicationSupportPath() async => _dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('webapp_assets_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('extrae el zip empaquetado y devuelve el directorio con index.html',
      () async {
    final dir = await WebappAssets.ensureExtracted();
    expect(dir, isNotNull);
    expect(await File('$dir/index.html').exists(), isTrue);
  });

  test('una segunda llamada reutiliza la extracción (misma marca de tamaño)',
      () async {
    final first = await WebappAssets.ensureExtracted();
    final marker = File('$first/.size');
    final firstStamp = await marker.readAsString();

    final second = await WebappAssets.ensureExtracted();
    expect(second, first);
    expect(await marker.readAsString(), firstStamp);
  });
}
