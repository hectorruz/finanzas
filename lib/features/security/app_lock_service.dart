import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Lógica de seguridad del bloqueo de la app. Delega la autenticación en el
/// sistema operativo: usa la biometría (huella/rostro) y, como alternativa, el
/// PIN/patrón/contraseña del propio teléfono. La app no almacena credenciales.
class AppLockService {
  AppLockService(this._auth);
  final LocalAuthentication _auth;

  /// ¿El dispositivo tiene una credencial segura configurada (PIN, patrón,
  /// contraseña o biometría)? Sin ella no tiene sentido activar el bloqueo.
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Lanza el diálogo nativo de autenticación. Acepta biometría o, si falla o
  /// no hay, la credencial del dispositivo. Devuelve `true` si se autenticó.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloquea Finanzas',
        options: const AuthenticationOptions(
          // biometricOnly: false → permite el PIN/patrón del teléfono.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(LocalAuthentication()),
);
