import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/sync_peer.dart';
import '../model/entity_change.dart';
import '../model/sync_decisions.dart';
import '../model/sync_plan.dart';
import '../sync_engine.dart';
import 'sync_identity.dart';
import 'sync_protocol.dart';

/// Sesión de revisión abierta en el admin cuando un vinculado envía su changelog.
/// Vive en memoria mientras dura el sync; el humano decide antes de aplicarla.
class ReviewSession {
  ReviewSession({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.since,
    required this.incoming,
    required this.plan,
  });

  final String id;
  final int peerId;
  final String peerName;
  final DateTime since;
  final List<EntityChange> incoming;
  final SyncPlan plan;

  SyncSessionStatus status = SyncSessionStatus.pending;
  List<EntityChange>? authoritative;
  DateTime? newWatermark;
}

/// Servidor HTTP del admin en la LAN. Sirve el emparejamiento (por PIN) y el
/// intercambio de cambios (con token). No decide nada por su cuenta: al recibir
/// un changelog abre una [ReviewSession] y avisa a la UI; el humano confirma y
/// entonces se aplica la fusión.
class LanSyncServer {
  LanSyncServer({
    required Isar isar,
    required SyncEngine engine,
    required this.identity,
    required this.pin,
    this.onSession,
  })  : _isar = isar,
        _engine = engine;

  final Isar _isar;
  final SyncEngine _engine;
  final SyncIdentity identity;
  final String pin;

  /// Se invoca cuando llega un changelog nuevo (para que la UI muestre "revisar").
  final void Function(ReviewSession)? onSession;

  final Map<String, ReviewSession> _sessions = {};
  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Sesiones abiertas (solo para tests / diagnóstico).
  @visibleForTesting
  List<ReviewSession> get debugSessions => _sessions.values.toList();

  Future<int> start({int port = SyncProtocol.defaultPort}) async {
    if (_server != null) return _server!.port;
    // anyIPv4 para aceptar conexiones de otros dispositivos de la LAN.
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port,
        shared: true);
    _server = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sessions.clear();
  }

  /// El admin confirma la revisión: aplica la fusión de forma atómica y deja el
  /// estado autoritativo listo para que el vinculado lo recoja.
  Future<void> finalizeSession(String sessionId, SyncDecisions decisions) async {
    final s = _sessions[sessionId];
    if (s == null) return;
    final ownChangelog = await _engine.buildChangelog(s.since);
    final result = await _engine.mergeAsAdmin(
      incoming: s.incoming,
      ownChangelog: ownChangelog,
      plan: s.plan,
      decisions: decisions,
      newWatermark: DateTime.now(),
      peerId: s.peerId,
    );
    s
      ..authoritative = result.authoritative
      ..newWatermark = result.newWatermark
      ..status = SyncSessionStatus.ready;
  }

  void rejectSession(String sessionId) {
    _sessions[sessionId]?.status = SyncSessionStatus.rejected;
  }

  // --- Enrutado ---

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'POST' && path == SyncProtocol.pairPath) {
        return await _handlePair(req);
      }
      // A partir de aquí, todo exige token válido.
      final peer = await _authenticate(req);
      if (peer == null) {
        return _json(req, 401, {'error': 'unauthorized'});
      }
      if (req.method == 'POST' && path == SyncProtocol.changelogPath) {
        return await _handleChangelog(req, peer);
      }
      if (req.method == 'GET' && path.startsWith('/sync/session/')) {
        return _handleSession(req, path.substring('/sync/session/'.length));
      }
      _json(req, 404, {'error': 'not_found'});
    } catch (e) {
      _json(req, 500, {'error': '$e'});
    }
  }

  Future<SyncPeer?> _authenticate(HttpRequest req) async {
    final header = req.headers.value(SyncProtocol.authHeader);
    final token = SyncProtocol.tokenFromHeader(header);
    if (token == null || token.isEmpty) return null;
    return _isar.syncPeers.filter().pairTokenEqualTo(token).findFirst();
  }

  Future<void> _handlePair(HttpRequest req) async {
    final body = await _readJson(req);
    if (body['pin'] != pin) {
      return _json(req, 403, {'error': 'bad_pin'});
    }
    final deviceId = body['deviceId'] as String? ?? '';
    if (deviceId.isEmpty) return _json(req, 400, {'error': 'no_device'});

    final token = generatePairToken();
    await _upsertPeer(
      deviceId,
      body['displayName'] as String? ?? 'Dispositivo',
      token: token,
      address: '${req.connectionInfo?.remoteAddress.address}',
    );

    _json(
      req,
      200,
      encodePairResponse(
        token: token,
        deviceId: identity.deviceId,
        displayName: identity.displayName,
      ),
    );
  }

  Future<void> _handleChangelog(HttpRequest req, SyncPeer peer) async {
    final body = await _readJson(req);
    final incoming = decodeChanges(body['changes']);
    final plan = await _engine.classifyIncoming(incoming, peer.watermark);

    final session = ReviewSession(
      id: const Uuid().v4(),
      peerId: peer.id,
      peerName: peer.displayName,
      since: peer.watermark,
      incoming: incoming,
      plan: plan,
    );
    _sessions[session.id] = session;
    onSession?.call(session);

    _json(req, 200, {
      'sessionId': session.id,
      'status': SyncSessionStatus.pending.name,
      'summary': {
        'new': plan.additions.length,
        'updates': plan.cleanUpdates.length,
        'conflicts': plan.conflicts.length,
      },
    });
  }

  void _handleSession(HttpRequest req, String id) {
    final s = _sessions[id];
    if (s == null) return _json(req, 404, {'error': 'no_session'});
    _json(
      req,
      200,
      encodeSessionResponse(
        status: s.status,
        authoritative: s.status == SyncSessionStatus.ready ? s.authoritative : null,
        newWatermark: s.newWatermark,
      ),
    );
  }

  // --- Utilidades ---

  Future<SyncPeer> _upsertPeer(String deviceId, String displayName,
      {String? token, String? address}) {
    return _isar.writeTxn(() async {
      final existing =
          await _isar.syncPeers.filter().deviceIdEqualTo(deviceId).findFirst();
      final peer = existing ?? (SyncPeer()..deviceId = deviceId);
      peer
        ..displayName = displayName
        ..remoteIsAdmin = false;
      if (token != null) peer.pairToken = token;
      if (address != null) peer.lastAddress = address;
      final id = await _isar.syncPeers.put(peer);
      peer.id = id;
      return peer;
    });
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    if (body.isEmpty) return {};
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }
}
