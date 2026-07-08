import 'dart:io';

import 'package:finanzas/core/db/isar_service.dart';
import 'package:isar_community/isar.dart';

/// Contador para dar un nombre único a cada instancia de Isar en los tests
/// (Isar no permite dos instancias abiertas con el mismo nombre).
int _seq = 0;

/// Descarga (una vez) el binario nativo de Isar para los tests que corren en la
/// Dart VM. Idempotente.
Future<void> initTestIsarCore() => Isar.initializeIsarCore(download: true);

/// Abre una instancia de Isar temporal y aislada con el esquema real de la app.
/// El llamador debe cerrarla con `isar.close(deleteFromDisk: true)`.
Future<Isar> openTestIsar() async {
  final dir = await Directory.systemTemp.createTemp('finanzas_test_');
  return Isar.open(
    kIsarSchemas,
    directory: dir.path,
    name: 'test_${_seq++}',
    inspector: false,
  );
}
