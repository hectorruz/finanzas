import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';
import 'lock_screen.dart';

/// Envuelve la app y muestra la [LockScreen] cuando procede: al arrancar en
/// frío y cada vez que la app vuelve de segundo plano, siempre que el bloqueo
/// esté activado en los ajustes.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  /// Solo pasa a `true` tras una autenticación correcta. Arrancamos sin
  /// desbloquear, de modo que si el bloqueo está activo se pide nada más abrir.
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al irse a segundo plano, re-armamos el bloqueo para exigir auth al volver.
    if (state == AppLifecycleState.paused && _unlocked) {
      setState(() => _unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si el usuario activa el bloqueo en caliente (false → true) no queremos
    // pedirle auth en ese mismo instante; solo en el siguiente arranque/regreso.
    // En cambio, en arranque en frío la transición es null/cargando → true, y
    // ahí sí debe bloquearse.
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final wasEnabled = prev?.valueOrNull?.appLockEnabled;
      final isEnabled = next.valueOrNull?.appLockEnabled;
      if (wasEnabled == false && isEnabled == true && !_unlocked) {
        setState(() => _unlocked = true);
      }
    });

    final enabled = ref.watch(currentSettingsProvider).appLockEnabled;
    final shouldLock = enabled && !_unlocked;

    return Stack(
      children: [
        widget.child,
        if (shouldLock)
          LockScreen(
            onUnlocked: () => setState(() => _unlocked = true),
          ),
      ],
    );
  }
}
