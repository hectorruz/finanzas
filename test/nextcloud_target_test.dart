import 'dart:convert';

import 'package:finanzas/features/backup/nextcloud_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// PROPFIND de ejemplo con 3 copias nuestras (+ la propia carpeta), de más
/// antigua a más nueva por el timestamp del nombre.
const _propfindBody = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/remote.php/dav/files/hector/Finanzas/</d:href></d:response>
  <d:response><d:href>/remote.php/dav/files/hector/Finanzas/finanzas_backup_2026-01-01T03-00-00.000.json</d:href></d:response>
  <d:response><d:href>/remote.php/dav/files/hector/Finanzas/finanzas_backup_2026-02-01T03-00-00.000.json</d:href></d:response>
  <d:response><d:href>/remote.php/dav/files/hector/Finanzas/finanzas_backup_2026-03-01T03-00-00.000.json</d:href></d:response>
</d:multistatus>''';

void main() {
  test('upload: MKCOL de la carpeta, PUT del fichero con Basic auth y URL correcta',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((req) async {
      requests.add(req);
      if (req.method == 'PROPFIND') {
        return http.Response(_propfindBody, 207);
      }
      return http.Response('', 201);
    });

    final target = NextcloudBackupTarget(
      baseUrl: 'https://nube.example.com/', // barra final que debe ignorarse
      user: 'hector',
      password: 'secret',
      folder: 'Finanzas',
      keepLast: 2,
      client: client,
    );

    await target.upload('finanzas_backup_2026-03-15T03-00-00.000.json',
        utf8.encode('{"ok":true}'));

    final mkcol = requests.firstWhere((r) => r.method == 'MKCOL');
    expect(mkcol.url.toString(),
        'https://nube.example.com/remote.php/dav/files/hector/Finanzas');

    final put = requests.firstWhere((r) => r.method == 'PUT');
    expect(
        put.url.toString(),
        'https://nube.example.com/remote.php/dav/files/hector/Finanzas/'
        'finanzas_backup_2026-03-15T03-00-00.000.json');
    expect(put.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('hector:secret'))}');
    expect(put.body, '{"ok":true}');
  });

  test('rotación: con keepLast=2 y 3 copias remotas borra la más antigua',
      () async {
    final deletes = <String>[];
    final client = MockClient((req) async {
      if (req.method == 'PROPFIND') return http.Response(_propfindBody, 207);
      if (req.method == 'DELETE') {
        deletes.add(req.url.toString());
        return http.Response('', 204);
      }
      return http.Response('', 201);
    });

    final target = NextcloudBackupTarget(
      baseUrl: 'https://nube.example.com',
      user: 'hector',
      password: 'secret',
      folder: 'Finanzas',
      keepLast: 2,
      client: client,
    );

    await target.upload('finanzas_backup_2026-03-15T03-00-00.000.json',
        utf8.encode('{}'));

    expect(deletes, hasLength(1));
    expect(deletes.single.endsWith('finanzas_backup_2026-01-01T03-00-00.000.json'),
        isTrue);
  });

  test('un 401 en el PUT lanza un error legible', () async {
    final client = MockClient((req) async {
      if (req.method == 'MKCOL') return http.Response('', 201);
      return http.Response('', 401, reasonPhrase: 'Unauthorized');
    });

    final target = NextcloudBackupTarget(
      baseUrl: 'https://nube.example.com',
      user: 'hector',
      password: 'mal',
      folder: 'Finanzas',
      client: client,
    );

    expect(
      () => target.upload('x.json', utf8.encode('{}')),
      throwsA(predicate((e) =>
          e.toString().contains('401') &&
          e.toString().contains('usuario o contraseña'))),
    );
  });
}
