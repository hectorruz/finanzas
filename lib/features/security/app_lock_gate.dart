import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import 'lock_screen.dart';

/// Envuelve la app y muestra la [LockScreen] cuando procede:
/// al arrancar en frío y cada vez que la app vuelve de segundo plano,
/// siempre que el bloqueo esté activado y haya un PIN configurado.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  /// Empezamos bloqueados; en el primer build se decide según los ajustes.
  bool _locked = true;
  bool _initialized = false;

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
    if (state == AppLifecycleState.paused) {
      final settings = ref.read(currentSettingsProvider);
      if (settings.appLockConfigured && !_locked) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);

    // Primera evaluación una vez cargados los ajustes: si no hay bloqueo,
    // arrancamos desbloqueados.
    if (!_initialized) {
      _initialized = true;
      _locked = settings.appLockConfigured;
    }

    // Si el usuario desactiva el bloqueo (o aún no lo configuró), nunca tapamos.
    final shouldLock = settings.appLockConfigured && _locked;

    return Stack(
      children: [
        widget.child,
        if (shouldLock)
          LockScreen(
            onUnlocked: () => setState(() => _locked = false),
          ),
      ],
    );
  }
}
