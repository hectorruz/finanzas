import 'dart:io';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../data/models/app_settings.dart';
import '../../../data/repositories/settings_repository.dart';

const _uuid = Uuid();

/// Identidad de sincronización de este dispositivo (uuid estable + nombre),
/// generada de forma perezosa la primera vez y guardada en [AppSettings].
class SyncIdentity {
  SyncIdentity({required this.deviceId, required this.displayName});
  final String deviceId;
  final String displayName;
}

/// Devuelve (creándola si hace falta) la identidad de sync de este dispositivo.
Future<SyncIdentity> ensureIdentity(SettingsRepository repo) async {
  final settings = await repo.getOrCreate();
  var id = settings.syncDeviceId;
  var name = settings.syncDeviceName;
  if (id.isEmpty || name.isEmpty) {
    await repo.update((s) {
      if (s.syncDeviceId.isEmpty) s.syncDeviceId = _uuid.v4();
      if (s.syncDeviceName.isEmpty) s.syncDeviceName = _defaultDeviceName();
    });
    final updated = await repo.getOrCreate();
    id = updated.syncDeviceId;
    name = updated.syncDeviceName;
  }
  return SyncIdentity(deviceId: id, displayName: name);
}

String _defaultDeviceName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return 'Dispositivo';
  }
}

/// Token de emparejamiento (secreto compartido de sesión).
String generatePairToken() => _uuid.v4().replaceAll('-', '');

/// PIN de 6 dígitos para el emparejamiento.
String generatePin() {
  final r = Random.secure();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

/// Direcciones IPv4 no-loopback de este dispositivo (para mostrar al usuario).
Future<List<String>> localIpv4Addresses() async {
  final out = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        out.add(addr.address);
      }
    }
  } catch (_) {
    // Sin permisos/entorno de red: devolvemos vacío y la UI pide IP manual.
  }
  return out;
}
