import 'dart:convert';
import 'dart:io';

import 'package:finanzas/features/backup/cloud_backup_provider.dart';
import 'package:finanzas/features/backup/nextcloud_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Nextcloud WebDAV mínimo, de mentira, para hablarle con el cliente de verdad
/// por el cable (mismo enfoque que `lan_sync_test.dart`: nada de mocks).
class _FakeWebDav {
  _FakeWebDav({this.requireAuth = true});

  final bool requireAuth;
  late final HttpServer _server;
  final Map<String, List<int>> files = {}; // ruta → contenido
  final Set<String> folders = {};
  final List<String> methods = [];
  String? lastAuthHeader;

  int get port => _server.port;

  static const _user = 'hector';
  static const _pass = 'app-token-1234';
  static String get _expectedAuth =>
      'Basic ${base64Encode(utf8.encode('$_user:$_pass'))}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    methods.add('${req.method} ${req.uri.path}');
    lastAuthHeader = req.headers.value('authorization');
    final res = req.response;

    if (requireAuth && lastAuthHeader != _expectedAuth) {
      res.statusCode = 401;
      await res.close();
      return;
    }

    final path = req.uri.path;
    switch (req.method) {
      case 'MKCOL':
        if (folders.contains(path)) {
          res.statusCode = 405; // ya existe
        } else {
          folders.add(path);
          res.statusCode = 201;
        }
        break;
      case 'PUT':
        files[path] = await _readBody(req);
        res.statusCode = 201;
        break;
      case 'GET':
        final content = files[path];
        if (content == null) {
          res.statusCode = 404;
        } else {
          res.add(content);
        }
        break;
      case 'DELETE':
        files.remove(path);
        res.statusCode = 204;
        break;
      case 'PROPFIND':
        await _readBody(req);
        res.statusCode = 207;
        res.headers.contentType = ContentType('application', 'xml');
        res.write(_multistatus(path));
        break;
      default:
        res.statusCode = 501;
    }
    await res.close();
  }

  Future<List<int>> _readBody(HttpRequest req) async {
    final out = <int>[];
    await for (final chunk in req) {
      out.addAll(chunk);
    }
    return out;
  }

  String _multistatus(String folderPath) {
    final buf = StringBuffer()
      ..write('<?xml version="1.0"?>')
      ..write('<d:multistatus xmlns:d="DAV:">')
      // la propia carpeta (debe ignorarse)
      ..write('<d:response><d:href>$folderPath/</d:href>'
          '<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
          '</d:prop></d:propstat></d:response>');
    for (final entry in files.entries) {
      if (!entry.key.startsWith(folderPath)) continue;
      buf.write('<d:response><d:href>${entry.key}</d:href>'
          '<d:propstat><d:prop>'
          '<d:getlastmodified>Fri, 17 Jul 2026 03:00:00 GMT</d:getlastmodified>'
          '<d:getcontentlength>${entry.value.length}</d:getcontentlength>'
          '<d:resourcetype/></d:prop></d:propstat></d:response>');
    }
    buf.write('</d:multistatus>');
    return buf.toString();
  }
}

void main() {
  _FakeWebDav? server;

  NextcloudBackupProvider providerFor(_FakeWebDav s,
          {String password = _FakeWebDav._pass}) =>
      NextcloudBackupProvider(
        baseUrl: 'http://${InternetAddress.loopbackIPv4.address}:${s.port}',
        user: _FakeWebDav._user,
        password: password,
        folder: 'Finanzas',
        client: http.Client(),
      );

  Future<_FakeWebDav> startServer({bool requireAuth = true}) async {
    final s = _FakeWebDav(requireAuth: requireAuth);
    await s.start();
    server = s;
    return s;
  }

  tearDown(() async {
    await server?.stop();
    server = null;
  });

  group('parseBaseUrl (puro)', () {
    test('antepone https si falta el esquema', () {
      expect(NextcloudBackupProvider.parseBaseUrl('cloud.example.com').scheme,
          'https');
    });
    test('respeta http explícito', () {
      expect(NextcloudBackupProvider.parseBaseUrl('http://192.168.1.5').scheme,
          'http');
    });
    test('quita las barras finales', () {
      expect(
          NextcloudBackupProvider.parseBaseUrl('https://cloud.example.com/')
              .toString(),
          'https://cloud.example.com');
    });
    test('una dirección vacía lanza', () {
      expect(() => NextcloudBackupProvider.parseBaseUrl('  '),
          throwsA(isA<CloudBackupException>()));
    });
  });

  group('parsePropfind (puro)', () {
    test('ignora la carpeta y las subcarpetas, extrae tamaño y fecha', () {
      const xml = '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>/dav/Finanzas/</d:href>'
          '<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
          '</d:prop></d:propstat></d:response>'
          '<d:response><d:href>/dav/Finanzas/finanzas_backup_2026-07-17T03-00-00Z.json</d:href>'
          '<d:propstat><d:prop>'
          '<d:getlastmodified>Fri, 17 Jul 2026 03:00:00 GMT</d:getlastmodified>'
          '<d:getcontentlength>1234</d:getcontentlength>'
          '<d:resourcetype/></d:prop></d:propstat></d:response>'
          '</d:multistatus>';
      final entries = parsePropfind(xml, '/dav/Finanzas');
      expect(entries.length, 1);
      expect(entries.first.name, 'finanzas_backup_2026-07-17T03-00-00Z.json');
      expect(entries.first.sizeBytes, 1234);
      expect(entries.first.modifiedAt, isNotNull);
    });
  });

  group('contra un WebDAV real', () {
    test('testConnection crea la carpeta (MKCOL) con Basic auth', () async {
      final s = await startServer();
      await providerFor(s).testConnection();
      expect(s.methods.any((m) => m.startsWith('MKCOL')), isTrue);
      expect(s.lastAuthHeader, _FakeWebDav._expectedAuth);
    });

    test('upload deja el fichero en la carpeta', () async {
      final s = await startServer();
      final p = providerFor(s);
      await p.upload('finanzas_backup_2026-07-17T03-00-00Z.json',
          utf8.encode('{"hola":1}'));
      expect(
          s.files.keys.any(
              (k) => k.endsWith('finanzas_backup_2026-07-17T03-00-00Z.json')),
          isTrue);
    });

    test('MKCOL 405 (carpeta ya existente) NO es un error', () async {
      final s = await startServer();
      final p = providerFor(s);
      await p.testConnection(); // crea la carpeta → 201
      await p.testConnection(); // segunda vez → 405, debe pasar sin lanzar
    });

    test('list sube, lista y descarga el ciclo completo', () async {
      final s = await startServer();
      final p = providerFor(s);
      await p.upload('finanzas_backup_2026-07-16T03-00-00Z.json',
          utf8.encode('{"a":1}'));
      await p.upload('finanzas_backup_2026-07-17T03-00-00Z.json',
          utf8.encode('{"b":2}'));
      final entries = await p.list();
      expect(entries.length, 2);
      final bytes = await p.download(
          entries.firstWhere((e) => e.name.contains('07-16')));
      expect(utf8.decode(bytes), '{"a":1}');
    });

    test('delete quita la copia', () async {
      final s = await startServer();
      final p = providerFor(s);
      await p.upload('finanzas_backup_2026-07-17T03-00-00Z.json',
          utf8.encode('{}'));
      final entries = await p.list();
      await p.delete(entries.single);
      expect(await p.list(), isEmpty);
    });

    test('401 se traduce a un CloudBackupException legible', () async {
      final s = await startServer();
      final p = providerFor(s, password: 'contraseña-mala');
      expect(
        () => p.testConnection(),
        throwsA(isA<CloudBackupException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('incorrect'))),
      );
    });
  });
}
