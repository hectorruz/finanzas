import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';

/// Valor efectivo de la privacidad de recientes: `null` en ajustes = activado
/// por defecto (ver `AppSettings.secureScreenEnabled`).
final secureScreenEnabledProvider = Provider<bool>(
  (ref) => ref.watch(currentSettingsProvider).secureScreenEnabled ?? true,
);

/// Superpone un velo difuminado con un ojo cuando la app deja de estar en primer
/// plano (multitarea, cambio de app, sombra de notificaciones), al estilo de las
/// apps de banca. Es el complemento visible de `FLAG_SECURE` (que ya oculta la
/// miniatura del sistema y bloquea capturas): tapa el contenido en vivo incluso
/// antes de que el SO tome la instantánea de recientes.
///
/// Modelado sobre `AppLockGate` (Stack + WidgetsBindingObserver).
class PrivacyScreenGate extends ConsumerStatefulWidget {
  const PrivacyScreenGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PrivacyScreenGate> createState() => _PrivacyScreenGateState();
}

class _PrivacyScreenGateState extends ConsumerState<PrivacyScreenGate>
    with WidgetsBindingObserver {
  bool _obscured = false;

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
    // Oculta en cuanto la app deja de estar activa (inactive cubre el momento en
    // que se abre el selector de tareas, antes de paused).
    final shouldObscure = state != AppLifecycleState.resumed;
    if (shouldObscure != _obscured) {
      setState(() => _obscured = shouldObscure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(secureScreenEnabledProvider);
    final show = enabled && _obscured;

    return Stack(
      children: [
        widget.child,
        if (show)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withOpacity(0.92),
                alignment: Alignment.center,
                child: Icon(
                  Icons.visibility_off_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
