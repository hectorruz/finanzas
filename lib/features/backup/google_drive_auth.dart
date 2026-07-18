/// Envoltorio fino de `google_sign_in` 7.x para obtener el token de Google
/// Drive. Aislado del proveedor REST para que ese sí se pueda testear con un
/// `http.Client` de mentira; esto de aquí necesita la plataforma y no se testea.
///
/// En la v7 `authenticate()` ya **no** devuelve token de acceso: primero se
/// autentica a la persona y luego se piden los scopes por separado, con
/// `authorizationForScopes` (silencioso) o `authorizeScopes` (interactivo). El
/// método de conveniencia `authorizationHeaders` encapsula justo ese "prueba en
/// silencio y, si hace falta, pregunta".
library;

import 'package:google_sign_in/google_sign_in.dart';

import 'cloud_backup_provider.dart';

/// Solo `drive.file`: acceso a los ficheros que crea la app, nada más. Es un
/// scope **no sensible**, así que la app no pasa por la verificación de
/// seguridad de Google. NO pedir `drive` ni `drive.readonly` (son *restricted*).
const kDriveScopes = <String>['https://www.googleapis.com/auth/drive.file'];

class GoogleDriveAuth {
  GoogleDriveAuth._();
  static final GoogleDriveAuth instance = GoogleDriveAuth._();

  bool _initialized = false;
  GoogleSignInAccount? _current;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    // `initialize()` debe llamarse una sola vez por instancia.
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  /// Cuenta conectada actualmente, si la hay (correo para la UI).
  String? get accountEmail => _current?.email;

  /// Login interactivo: muestra el selector de cuenta y pide el scope. Devuelve
  /// el correo de la cuenta conectada. Lanza [CloudBackupException] si la
  /// persona cancela o hay un error.
  Future<String> connect() async {
    await _ensureInitialized();
    try {
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: kDriveScopes);
      _current = account;
      // Fuerza la concesión del scope aquí, con UI disponible, para que las
      // copias posteriores puedan resolverlo en silencio.
      await account.authorizationClient.authorizeScopes(kDriveScopes);
      return account.email;
    } on GoogleSignInException catch (e) {
      throw CloudBackupException(_message(e));
    }
  }

  Future<void> disconnect() async {
    await _ensureInitialized();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Cerrar sesión es best-effort: si falla, la reconexión lo resuelve.
    }
    _current = null;
  }

  /// Cabeceras `Authorization: Bearer …` para las llamadas REST.
  ///
  /// [interactive] = false (el caso de las copias automáticas): intenta
  /// recuperar la sesión y el token **sin UI**; si no puede, devuelve `null` en
  /// vez de lanzar, y quien llama lo trata como "hay que reconectar".
  /// [interactive] = true: puede mostrar el selector/consentimiento.
  Future<Map<String, String>?> authHeaders({required bool interactive}) async {
    await _ensureInitialized();
    try {
      var account = _current;
      account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) {
        if (!interactive) return null;
        account = await GoogleSignIn.instance.authenticate(scopeHint: kDriveScopes);
      }
      _current = account;
      return account.authorizationClient
          .authorizationHeaders(kDriveScopes, promptIfNecessary: interactive);
    } on GoogleSignInException catch (e) {
      if (!interactive) return null;
      throw CloudBackupException(_message(e));
    }
  }

  String _message(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Conexión con Google cancelada.';
      default:
        return 'No se pudo conectar con Google Drive: ${e.description ?? e.code.name}.';
    }
  }
}
