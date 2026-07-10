import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../../data/models/sync_peer.dart';
import '../../data/repositories/settings_repository.dart';
import 'model/sync_decisions.dart';
import 'net/lan_sync_client.dart';
import 'net/lan_sync_server.dart';
import 'net/sync_foreground_service.dart';
import 'net/sync_identity.dart';
import 'net/sync_protocol.dart';
import 'net/webapp_assets.dart';
import 'sync_engine.dart';

// ===================== Lado ADMIN: servidor =====================

class SyncServerState {
  const SyncServerState({
    this.running = false,
    this.port,
    this.ips = const [],
    this.pin = '',
    this.requirePin = true,
    this.pending = const [],
    this.error,
  });

  final bool running;
  final int? port;
  final List<String> ips;
  final String pin;

  /// Si el emparejamiento exige PIN. Si es `false`, [pin] va vacío y la UI
  /// indica que no hace falta código.
  final bool requirePin;
  final List<ReviewSession> pending;
  final String? error;

  SyncServerState copyWith({
    bool? running,
    int? port,
    List<String>? ips,
    String? pin,
    bool? requirePin,
    List<ReviewSession>? pending,
    String? error,
  }) =>
      SyncServerState(
        running: running ?? this.running,
        port: port ?? this.port,
        ips: ips ?? this.ips,
        pin: pin ?? this.pin,
        requirePin: requirePin ?? this.requirePin,
        pending: pending ?? this.pending,
        error: error,
      );
}

/// Controla el ciclo de vida del servidor LAN del admin y expone las sesiones
/// de revisión pendientes para que la UI las muestre.
class SyncServerController extends StateNotifier<SyncServerState> {
  SyncServerController(this._isar, this._engine, this._settings)
      : super(const SyncServerState());

  final Isar _isar;
  final SyncEngine _engine;
  final SettingsRepository _settings;
  LanSyncServer? _server;

  Future<void> start() async {
    if (state.running) return;
    try {
      final settings = await _settings.getOrCreate();
      final identity = await ensureIdentity(_settings);
      final requirePin = settings.syncRequirePin;
      // PIN fijo si el usuario lo configuró; si no, aleatorio en cada arranque.
      // Sin PIN si el emparejamiento no lo exige (red de confianza).
      final pin = requirePin
          ? (settings.syncFixedPin.trim().isNotEmpty
              ? settings.syncFixedPin.trim()
              : generatePin())
          : '';
      // Si el build de la webapp está empaquetado (`assets/webapp.zip`), se
      // sirve desde aquí mismo; si no, el servidor sigue funcionando igual
      // (solo API) y `_serveStatic` muestra el placeholder.
      final webRoot = await WebappAssets.ensureExtracted();
      final server = LanSyncServer(
        isar: _isar,
        engine: _engine,
        identity: identity,
        pin: pin,
        requirePin: requirePin,
        onSession: _onSession,
        webRoot: webRoot,
      );
      final desiredPort =
          settings.syncPort > 0 ? settings.syncPort : SyncProtocol.defaultPort;
      final port = await server.start(port: desiredPort);
      _server = server;
      final ips = await localIpv4Addresses();
      state = state.copyWith(
        running: true,
        port: port,
        pin: pin,
        requirePin: requirePin,
        ips: ips,
        pending: const [],
        error: null,
      );
      // Mantener vivo el servidor en segundo plano (servicio en primer plano).
      if (settings.syncKeepAliveInBackground) {
        await startSyncForegroundService(address: _addressFor(ips, port));
      }
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    await stopSyncForegroundService();
    state = const SyncServerState();
  }

  /// Reinicia el servidor (para aplicar cambios de puerto/PIN sin perder el
  /// estado del controlador). No hace nada si no estaba activo.
  Future<void> restart() async {
    if (!state.running) return;
    await stop();
    await start();
  }

  /// Arranca/detiene el servicio en primer plano en caliente al cambiar el
  /// interruptor con el servidor ya activo.
  Future<void> applyKeepAlive(bool enabled) async {
    if (!state.running) return;
    if (enabled) {
      await startSyncForegroundService(
        address: _addressFor(state.ips, state.port ?? SyncProtocol.defaultPort),
      );
    } else {
      await stopSyncForegroundService();
    }
  }

  /// Revoca el acceso de **todos** los dispositivos vinculados de golpe (borra
  /// sus tokens: su próxima petición dará 401 y tendrán que reemparejarse).
  Future<void> revokeAllLinkedPeers() async {
    await _isar.writeTxn(() async {
      final ids = await _isar.syncPeers
          .filter()
          .remoteIsAdminEqualTo(false)
          .idProperty()
          .findAll();
      await _isar.syncPeers.deleteAll(ids);
    });
  }

  String _addressFor(List<String> ips, int port) =>
      ips.isNotEmpty ? 'http://${ips.first}:$port' : 'Puerto $port';

  void _onSession(ReviewSession s) {
    state = state.copyWith(pending: [...state.pending, s]);
  }

  Future<void> finalizeSession(ReviewSession s, SyncDecisions decisions) async {
    await _server?.finalizeSession(s.id, decisions);
    _drop(s);
  }

  void rejectSession(ReviewSession s) {
    _server?.rejectSession(s.id);
    _drop(s);
  }

  /// Revoca el acceso de un dispositivo vinculado (borra su token: su próxima
  /// petición recibirá 401 y tendrá que volver a emparejarse con el PIN).
  Future<void> forgetLinkedPeer(int peerId) async {
    await _isar.writeTxn(() => _isar.syncPeers.delete(peerId));
  }

  void _drop(ReviewSession s) {
    state = state.copyWith(
        pending: state.pending.where((e) => e.id != s.id).toList());
  }

  @override
  void dispose() {
    _server?.stop();
    stopSyncForegroundService();
    super.dispose();
  }
}

final syncServerControllerProvider =
    StateNotifierProvider<SyncServerController, SyncServerState>((ref) {
  return SyncServerController(
    ref.watch(isarProvider),
    ref.watch(syncEngineProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

/// Dispositivos vinculados que ya se emparejaron con este admin (para
/// mostrarlos y poder revocar su acceso), independientemente de si tienen una
/// sesión de revisión pendiente ahora mismo.
final linkedPeersProvider = StreamProvider<List<SyncPeer>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.syncPeers
      .filter()
      .remoteIsAdminEqualTo(false)
      .watch(fireImmediately: true);
});

// ===================== Lado VINCULADO: cliente =====================

/// Resultado de un sync desde el vinculado.
class SyncOutcome {
  SyncOutcome({required this.applied, required this.rejected});
  final int applied;
  final bool rejected;
}

/// Orquesta el sync desde el dispositivo vinculado: empareja (si hace falta),
/// envía su changelog, espera la decisión del admin y reconcilia su BD.
class LinkedSyncService {
  LinkedSyncService(this._isar, this._engine, this._settings);
  final Isar _isar;
  final SyncEngine _engine;
  final SettingsRepository _settings;

  /// Empareja con el admin en `host:port` usando el [pin]. Guarda el admin como
  /// par (con su token) y devuelve su nombre.
  Future<String> pair({
    required String host,
    required int port,
    required String pin,
  }) async {
    final identity = await ensureIdentity(_settings);
    final client = LanSyncClient(host: host, port: port);
    try {
      final res = await client.pair(
          pin: pin,
          deviceId: identity.deviceId,
          displayName: identity.displayName);
      await _upsertAdminPeer(res, host, port);
      return res.displayName;
    } finally {
      client.close();
    }
  }

  /// Ejecuta un sync completo contra el admin ya emparejado en `host:port`.
  Future<SyncOutcome> sync({
    required String host,
    required int port,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    final identity = await ensureIdentity(_settings);
    final admins =
        await _isar.syncPeers.filter().remoteIsAdminEqualTo(true).findAll();
    final peer = admins.firstWhere(
      (p) => p.lastAddress == '$host:$port' && p.pairToken.isNotEmpty,
      orElse: () => admins.firstWhere((p) => p.pairToken.isNotEmpty,
          orElse: SyncPeer.new),
    );
    if (peer.pairToken.isEmpty) {
      throw StateError('No emparejado: empareja primero con el admin.');
    }

    final client = LanSyncClient(host: host, port: port, token: peer.pairToken);
    try {
      final changes = await _engine.buildChangelog(peer.watermark);
      final pushed = await client.pushChangelog(
          deviceId: identity.deviceId, changes: changes);

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final session = await client.pollSession(pushed.sessionId);
        if (session.status == SyncSessionStatus.rejected) {
          return SyncOutcome(applied: 0, rejected: true);
        }
        if (session.status == SyncSessionStatus.ready) {
          final auth = session.authoritative ?? const [];
          await _engine.reconcileAsLinked(
            auth,
            newWatermark: session.newWatermark ?? DateTime.now(),
            peerId: peer.id,
          );
          return SyncOutcome(applied: auth.length, rejected: false);
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException('El admin no confirmó a tiempo.');
    } finally {
      client.close();
    }
  }

  /// Admins ya emparejados con este dispositivo (guardados localmente): permite
  /// reconectar sin volver a teclear IP/puerto/PIN cada vez.
  Future<List<SyncPeer>> savedAdminPeers() =>
      _isar.syncPeers.filter().remoteIsAdminEqualTo(true).findAll();

  /// Olvida un admin guardado (borra el token local; para volver a sincronizar
  /// con él hará falta emparejarse de nuevo con su PIN).
  Future<void> forgetAdmin(int peerId) async {
    await _isar.writeTxn(() => _isar.syncPeers.delete(peerId));
  }

  /// Intenta sincronizar con todos los admins guardados sin molestar: pensado
  /// para lanzarse solo al abrir/reanudar la app, para que el vinculado no
  /// tenga que entrar a propósito a la pantalla de sync cada vez. Cualquier
  /// error (el admin no está en la misma red ahora mismo, timeout, etc.) se
  /// silencia — el usuario siempre puede sincronizar a mano si hace falta.
  Future<void> tryBackgroundSyncAll() async {
    for (final peer in await savedAdminPeers()) {
      final parts = peer.lastAddress.split(':');
      if (parts.length != 2 || peer.pairToken.isEmpty) continue;
      final port = int.tryParse(parts[1]);
      if (port == null) continue;
      try {
        await sync(
          host: parts[0],
          port: port,
          timeout: const Duration(seconds: 8),
          pollInterval: const Duration(milliseconds: 300),
        );
      } catch (_) {
        // Silencioso a propósito: ver doc del método.
      }
    }
  }

  Future<void> _upsertAdminPeer(PairResult res, String host, int port) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.syncPeers
          .filter()
          .deviceIdEqualTo(res.deviceId)
          .findFirst();
      final peer = existing ?? (SyncPeer()..deviceId = res.deviceId);
      peer
        ..displayName = res.displayName
        ..remoteIsAdmin = true
        ..pairToken = res.token
        ..lastAddress = '$host:$port';
      await _isar.syncPeers.put(peer);
    });
  }
}

final linkedSyncServiceProvider = Provider<LinkedSyncService>((ref) {
  return LinkedSyncService(
    ref.watch(isarProvider),
    ref.watch(syncEngineProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

/// Admins guardados en este dispositivo (vinculado): permite mostrar una
/// lista de reconexión rápida sin volver a teclear IP/puerto/PIN.
final savedAdminPeersProvider = StreamProvider<List<SyncPeer>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.syncPeers
      .filter()
      .remoteIsAdminEqualTo(true)
      .watch(fireImmediately: true);
});
