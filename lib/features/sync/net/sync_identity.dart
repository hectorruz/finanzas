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
///
/// Se filtran/ordenan para mostrar **solo la red LAN buena**: se prioriza el
/// rango de una Wi-Fi doméstica y se devuelven **solo** las direcciones del
/// primer rango presente, para no confundir con IPs de datos móviles, VPN o
/// interfaces virtuales (p. ej. una `10.x` junto a la `192.168.x` real).
Future<List<String>> localIpv4Addresses() async {
  final all = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        all.add(addr.address);
      }
    }
  } catch (_) {
    // Sin permisos/entorno de red: devolvemos vacío y la UI pide IP manual.
  }
  return preferLanAddresses(all);
}

/// Rango de prioridad de una IPv4: menor = mejor. `-1` = descartar
/// (link-local `169.254.x`, no sirve para hablar con otro dispositivo).
int _ipv4Rank(String ip) {
  if (ip.startsWith('169.254.')) return -1; // link-local: inútil
  if (ip.startsWith('192.168.')) return 0; // Wi-Fi doméstica típica
  if (_is172Private(ip)) return 1; // 172.16.0.0/12
  if (ip.startsWith('10.')) return 2; // datos móviles/VPN/redes grandes
  return 3; // cualquier otra ruteable
}

bool _is172Private(String ip) {
  if (!ip.startsWith('172.')) return false;
  final second = int.tryParse(ip.split('.').elementAt(1));
  return second != null && second >= 16 && second <= 31;
}

/// De todas las IPv4 locales, devuelve **solo** las del rango de mayor prioridad
/// presente (ver [_ipv4Rank]). Función pura para poder testearla sin red.
List<String> preferLanAddresses(List<String> addresses) {
  final ranked = addresses
      .map((ip) => (ip: ip, rank: _ipv4Rank(ip)))
      .where((e) => e.rank >= 0)
      .toList();
  if (ranked.isEmpty) return const [];
  final best = ranked.map((e) => e.rank).reduce((a, b) => a < b ? a : b);
  return [
    for (final e in ranked)
      if (e.rank == best) e.ip,
  ];
}
