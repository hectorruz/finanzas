import 'package:isar_community/isar.dart';

part 'sync_peer.g.dart';

/// Dispositivo emparejado para sincronizar, junto con el punto de corte
/// (watermark) del último sync correcto con él.
///
/// Es estado **local del dispositivo** (no se sincroniza ni se incluye en el
/// backup): cada móvil recuerda a sus pares y hasta dónde llegó con cada uno.
@Collection(accessor: 'syncPeers')
class SyncPeer {
  Id id = Isar.autoIncrement;

  /// Identidad estable del dispositivo par (su `syncDeviceId`).
  @Index(unique: true, replace: true)
  late String deviceId;

  /// Nombre legible para mostrar en la UI de sincronización.
  String displayName = '';

  /// Si el par actúa como admin (árbitro) en la relación con este dispositivo.
  bool remoteIsAdmin = false;

  /// Marca temporal del último sync correcto: los cambios con `updatedAt` mayor
  /// que esto son los que se intercambian en el siguiente sync. Solo avanza tras
  /// una fusión confirmada por ambas partes.
  DateTime watermark = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cuándo se completó el último sync con este par (informativo).
  DateTime? lastSyncAt;

  SyncPeer();
}
