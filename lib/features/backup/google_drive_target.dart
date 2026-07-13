import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'backup_target.dart';

/// Autorización con Google para las copias en Drive. Usa **solo el flujo de
/// autorización** de `google_sign_in` 7.x (no la autenticación con Credential
/// Manager): así basta con una credencial OAuth de tipo **Android** en Google
/// Cloud (paquete + SHA-1) y **no** hace falta un client id de tipo Web,
/// `serverClientId` ni `google-services.json`. Expone lo justo para la UI
/// (conectar/desconectar, ¿hay conexión?) y para el destino (cliente
/// autorizado silencioso, apto para el worker en segundo plano).
class GoogleDriveAuth {
  GoogleDriveAuth._();

  /// Solo ficheros creados por la app (`drive.file`): evita pedir permisos
  /// sensibles y la verificación de Google sobre scopes restringidos.
  static const scope = drive.DriveApi.driveFileScope;

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  static GoogleSignInAuthorizationClient get _authz =>
      GoogleSignIn.instance.authorizationClient;

  /// Autoriza el scope de Drive **interactivamente** (elegir cuenta +
  /// consentimiento) y devuelve el email de la cuenta (best-effort, vía
  /// `about.get`). **Solo** desde la UI en primer plano.
  static Future<String> connect() async {
    await ensureInitialized();
    final authz = await _authz.authorizeScopes(const [scope]);
    final client = authz.authClient(scopes: const [scope]);
    try {
      final about = await drive.DriveApi(client).about.get($fields: 'user');
      return about.user?.emailAddress ??
          about.user?.displayName ??
          'Cuenta de Google';
    } catch (_) {
      return 'Cuenta de Google';
    } finally {
      client.close();
    }
  }

  /// Revoca la autorización de la app.
  static Future<void> disconnect() async {
    await ensureInitialized();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      // Best-effort: aunque falle la revocación remota, olvidamos la cuenta.
    }
  }

  /// Cliente autorizado para Drive **sin** interacción (worker / segundo
  /// plano): `null` si el scope no puede autorizarse en silencio (habría que
  /// (re)conectar desde la UI). El tipo devuelto (`AuthClient`) implementa
  /// `http.Client`.
  static Future<http.Client?> silentAuthClient() async {
    await ensureInitialized();
    final authz = await _authz.authorizationForScopes(const [scope]);
    if (authz == null) return null;
    return authz.authClient(scopes: const [scope]);
  }
}

/// Sube las copias a una carpeta de **Google Drive** (por defecto "Finanzas")
/// usando el scope `drive.file`. Autenticación silenciosa: la cuenta se conecta
/// una vez desde Ajustes y a partir de ahí el worker sube sin interacción.
/// Rota (borra las más antiguas) conservando como mucho [keepLast].
class GoogleDriveBackupTarget implements BackupTarget {
  GoogleDriveBackupTarget({this.keepLast = 10, this.folderName = 'Finanzas'});

  final int keepLast;
  final String folderName;

  @override
  String get label => 'Google Drive';

  @override
  Future<void> upload(String filename, List<int> bytes) async {
    final client = await GoogleDriveAuth.silentAuthClient();
    if (client == null) {
      throw Exception('No hay una cuenta de Google conectada. Conéctala en '
          'Ajustes → Copias de seguridad.');
    }
    try {
      final api = drive.DriveApi(client);
      final folderId = await _ensureFolder(api);
      final meta = drive.File()
        ..name = filename
        ..parents = [folderId];
      final media = drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );
      await api.files.create(meta, uploadMedia: media);
      await _rotate(api, folderId);
    } finally {
      client.close();
    }
  }

  /// Id de la carpeta destino, creándola si no existe. Con `drive.file` solo se
  /// ven los ficheros/carpetas creados por la app, así que esta búsqueda solo
  /// encuentra "nuestra" carpeta.
  Future<String> _ensureFolder(drive.DriveApi api) async {
    final res = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and "
          "name='$folderName' and trashed=false",
      $fields: 'files(id,name)',
      spaces: 'drive',
    );
    final existing = res.files;
    if (existing != null && existing.isNotEmpty) return existing.first.id!;
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(folder);
    return created.id!;
  }

  Future<void> _rotate(drive.DriveApi api, String folderId) async {
    if (keepLast <= 0) return;
    try {
      final res = await api.files.list(
        q: "'$folderId' in parents and trashed=false and "
            "name contains 'finanzas_backup_'",
        $fields: 'files(id,name)',
        orderBy: 'name', // ascendente: el nombre lleva la fecha ISO
        spaces: 'drive',
        pageSize: 1000,
      );
      final files = res.files ?? [];
      final excess = files.length - keepLast;
      for (var i = 0; i < excess; i++) {
        try {
          await api.files.delete(files[i].id!);
        } catch (_) {}
      }
    } catch (_) {
      // Rotación best-effort: no invalida la copia ya subida.
    }
  }
}
