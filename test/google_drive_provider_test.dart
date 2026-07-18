import 'dart:convert';
import 'dart:io';

import 'package:finanzas/features/backup/cloud_backup_provider.dart';
import 'package:finanzas/features/backup/google_drive_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Drive REST mínimo, de mentira. No cubre google_sign_in (el token se inyecta):
/// verifica que el proveedor arma bien las peticiones y parsea las respuestas.
class _FakeDrive {
  late final HttpServer _server;
  final Map<String, Map<String, dynamic>> files = {}; // id → {name, parents}
  final Map<String, List<int>> contents = {};
  final List<String> requests = [];
  int _seq = 0;
  String? folderId;

  int get port => _server.port;
  Uri get apiBase =>
      Uri.parse('http://${InternetAddress.loopbackIPv4.address}:$port/drive/v3');
  Uri get uploadBase => Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:$port/upload/drive/v3');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    requests.add('${req.method} ${req.uri.path}');
    final res = req.response;
    final isUpload = req.uri.path.startsWith('/upload');
    final q = req.uri.queryParameters['q'] ?? '';

    if (req.method == 'POST' && isUpload) {
      // Subida multipart: extraemos el nombre del metadato JSON embebido.
      final body = await _readBody(req);
      final text = utf8.decode(body);
      final nameMatch = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(text);
      final id = 'file${_seq++}';
      files[id] = {'name': nameMatch?.group(1) ?? 'sin-nombre'};
      contents[id] = body;
      _json(res, {'id': id, 'name': files[id]!['name']});
      return;
    }
    if (req.method == 'POST') {
      // Crear carpeta.
      await _readBody(req);
      folderId = 'folder0';
      _json(res, {'id': folderId});
      return;
    }
    if (req.method == 'GET' && req.uri.queryParameters.containsKey('alt')) {
      final id = req.uri.pathSegments.last;
      res.add(contents[id] ?? const []);
      await res.close();
      return;
    }
    if (req.method == 'GET') {
      if (q.contains('mimeType')) {
        // Búsqueda de carpeta: aún no existe.
        _json(res, {'files': <dynamic>[]});
      } else {
        // Listado de ficheros de la carpeta.
        _json(res, {
          'files': files.entries
              .map((e) => {'id': e.key, 'name': e.value['name']})
              .toList()
        });
      }
      return;
    }
    if (req.method == 'DELETE') {
      final id = req.uri.pathSegments.last;
      files.remove(id);
      contents.remove(id);
      res.statusCode = 204;
      await res.close();
      return;
    }
    res.statusCode = 501;
    await res.close();
  }

  void _json(HttpResponse res, Object data) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(data));
    res.close();
  }

  Future<List<int>> _readBody(HttpRequest req) async {
    final out = <int>[];
    await for (final c in req) {
      out.addAll(c);
    }
    return out;
  }
}

void main() {
  late _FakeDrive server;

  GoogleDriveBackupProvider providerFor(_FakeDrive s) =>
      GoogleDriveBackupProvider(
        folder: 'Finanzas',
        headersProvider: () async => {'authorization': 'Bearer test-token'},
        client: http.Client(),
        apiBase: s.apiBase,
        uploadBase: s.uploadBase,
      );

  setUp(() async {
    server = _FakeDrive();
    await server.start();
  });
  tearDown(() async => server.stop());

  test('sube creando la carpeta la primera vez y cachea su id', () async {
    final p = providerFor(server);
    await p.upload('finanzas_backup_2026-07-17T03-00-00Z.json',
        utf8.encode('{"x":1}'));
    expect(p.resolvedFolderId, isNotNull);
    // La segunda subida no vuelve a buscar/crear la carpeta.
    final creates = server.requests
        .where((r) => r.startsWith('POST /drive/v3/files'))
        .length;
    await p.upload('finanzas_backup_2026-07-18T03-00-00Z.json',
        utf8.encode('{"y":2}'));
    final creates2 = server.requests
        .where((r) => r.startsWith('POST /drive/v3/files'))
        .length;
    expect(creates2, creates, reason: 'no debe recrear la carpeta');
  });

  test('lista, descarga y borra', () async {
    final p = providerFor(server);
    await p.upload('finanzas_backup_2026-07-17T03-00-00Z.json',
        utf8.encode('{"a":1}'));
    final entries = await p.list();
    expect(entries.length, 1);
    expect(entries.first.name, 'finanzas_backup_2026-07-17T03-00-00Z.json');

    final bytes = await p.download(entries.first);
    expect(utf8.decode(bytes), contains('"a":1'));

    await p.delete(entries.first);
    expect(await p.list(), isEmpty);
  });

  test('sin token lanza pidiendo reconectar', () async {
    final p = GoogleDriveBackupProvider(
      folder: 'Finanzas',
      headersProvider: () async => null,
      client: http.Client(),
      apiBase: server.apiBase,
      uploadBase: server.uploadBase,
    );
    expect(
      () => p.list(),
      throwsA(isA<CloudBackupException>()
          .having((e) => e.message, 'message', contains('conectar'))),
    );
  });
}
