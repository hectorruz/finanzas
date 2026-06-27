import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/models/app_settings.dart';

/// Lógica de seguridad del bloqueo de la app: biometría (huella/cara) y
/// verificación del PIN. El PIN nunca se guarda en claro: se almacena un hash
/// SHA-256 con un salt aleatorio (ver [AppSettings.pinHash]/`pinSalt`).
class AppLockService {
  AppLockService(this._auth);
  final LocalAuthentication _auth;

  /// ¿El dispositivo tiene biometría utilizable (huella, rostro…)?
  Future<bool> biometricsAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Lanza el diálogo nativo de biometría. Devuelve `true` si se autenticó.
  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloquea Finanzas',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Genera un salt aleatorio (16 bytes) en hexadecimal.
  String generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Hash del PIN combinado con su salt.
  String hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  /// Comprueba un PIN introducido contra el hash almacenado.
  bool verifyPin(AppSettings settings, String pin) {
    if (settings.pinHash.isEmpty) return false;
    return hashPin(pin, settings.pinSalt) == settings.pinHash;
  }
}

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(LocalAuthentication()),
);

/// ¿Hay biometría disponible en este dispositivo? (cacheado por sesión)
final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockServiceProvider).biometricsAvailable(),
);
