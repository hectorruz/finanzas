import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/sync_peer.dart';
import '../model/entity_change.dart';
import '../model/sync_decisions.dart';
import '../model/sync_plan.dart';
import '../sync_engine.dart';
import 'data_api.dart';
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
    this.requirePin = true,
    this.onSession,
    this.webRoot,
  })  : _isar = isar,
        _engine = engine,
        _dataApi = DataApi(isar);

  final Isar _isar;
  final SyncEngine _engine;
  final DataApi _dataApi;
  final SyncIdentity identity;
  final String pin;

  /// Si es `false`, el emparejamiento **no exige PIN** (red de confianza): se
  /// acepta cualquier `POST /pair`. Solo se debería desactivar en una LAN
  /// doméstica de confianza (ver ajustes avanzados del servidor).
  final bool requirePin;

  /// Carpeta con el build de la webapp de escritorio (`build/web`) a servir. Si
  /// es null o no existe, el servidor solo ofrece la API (sin webapp embebida).
  final String? webRoot;

  /// Se invoca cuando llega un changelog nuevo (para que la UI muestre "revisar").
  final void Function(ReviewSession)? onSession;

  final Map<String, ReviewSession> _sessions = {};
  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Sesiones abiertas (solo para tests / diagnóstico).
  List<ReviewSession> get debugSessions => _sessions.values.toList();

  Future<int> start({int port = SyncProtocol.defaultPort}) async {
    if (_server != null) return _server!.port;
    // anyIPv4 para aceptar conexiones de otros dispositivos de la LAN.
    final server =
        await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
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
  Future<void> finalizeSession(
      String sessionId, SyncDecisions decisions) async {
    final s = _sessions[sessionId];
    if (s == null) return;
    await _finalize(s, decisions);
  }

  Future<void> _finalize(ReviewSession s, SyncDecisions decisions) async {
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
      _cors(req);
      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.noContent;
        return req.response.close();
      }

      final path = req.uri.path;
      // Emparejamiento: sin token (autenticado por PIN).
      if (req.method == 'POST' && path == SyncProtocol.pairPath) {
        return await _handlePair(req);
      }

      // API de datos y sync: exigen token válido.
      if (DataApi.handles(path) || path.startsWith('/sync/')) {
        final peer = await _authenticate(req);
        if (peer == null) return _json(req, 401, {'error': 'unauthorized'});
        if (DataApi.handles(path)) return await _dataApi.handle(req);
        if (req.method == 'POST' && path == SyncProtocol.changelogPath) {
          return await _handleChangelog(req, peer);
        }
        if (req.method == 'GET' && path.startsWith('/sync/session/')) {
          return _handleSession(req, path.substring('/sync/session/'.length));
        }
        return _json(req, 404, {'error': 'not_found'});
      }

      // Resto: assets estáticos de la webapp (sin token: es solo la UI; los
      // datos siempre van por la API con token).
      await _serveStatic(req);
    } catch (e) {
      _json(req, 500, {'error': '$e'});
    }
  }

  void _cors(HttpRequest req) {
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'authorization, content-type');
  }

  Future<void> _serveStatic(HttpRequest req) async {
    final root = webRoot;
    if (root == null) return _json(req, 404, {'error': 'no_webapp'});
    var rel = req.uri.path == '/' ? 'index.html' : req.uri.path.substring(1);
    if (rel.contains('..')) return _json(req, 403, {'error': 'forbidden'});
    var file = File('$root/$rel');
    // Fallback SPA: cualquier ruta desconocida sirve index.html.
    if (!file.existsSync()) file = File('$root/index.html');
    if (!file.existsSync()) return _json(req, 404, {'error': 'not_found'});
    req.response.headers.contentType = _contentTypeFor(file.path);
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  ContentType _contentTypeFor(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js')) return ContentType('application', 'javascript');
    if (path.endsWith('.css')) return ContentType('text', 'css');
    if (path.endsWith('.json')) return ContentType.json;
    if (path.endsWith('.png')) return ContentType('image', 'png');
    if (path.endsWith('.svg')) return ContentType('image', 'svg+xml');
    if (path.endsWith('.wasm')) return ContentType('application', 'wasm');
    return ContentType.binary;
  }

  Future<SyncPeer?> _authenticate(HttpRequest req) async {
    final header = req.headers.value(SyncProtocol.authHeader);
    final token = SyncProtocol.tokenFromHeader(header);
    if (token == null || token.isEmpty) return null;
    return _isar.syncPeers.filter().pairTokenEqualTo(token).findFirst();
  }

  Future<void> _handlePair(HttpRequest req) async {
    final body = await _readJson(req);
    if (requirePin && body['pin'] != pin) {
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

    if (plan.conflicts.isEmpty) {
      // No hay nada que **decidir**: solo altas y/o actualizaciones limpias (o
      // una consulta vacía de "¿qué hay nuevo?"). Se resuelve sola con las
      // decisiones por defecto (aceptar todo lo entrante; ver
      // `SyncEngine._resolveApproved`), así el vinculado recibe también los
      // cambios propios del admin sin que nadie tenga que confirmar una sesión.
      // Solo se pide revisión humana cuando hay un conflicto real (ambos lados
      // tocaron la misma entidad desde el último watermark).
      await _finalize(session, SyncDecisions());
    } else {
      onSession?.call(session);
    }

    _json(req, 200, {
      'sessionId': session.id,
      'status': session.status.name,
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
        authoritative:
            s.status == SyncSessionStatus.ready ? s.authoritative : null,
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
