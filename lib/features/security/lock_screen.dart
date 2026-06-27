import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lock_service.dart';

/// Pantalla a pantalla completa que cubre la app mientras está bloqueada.
/// Lanza la autenticación del sistema (biometría o PIN del teléfono) y, si el
/// usuario la cancela, ofrece un botón para reintentar.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  /// Se invoca cuando el usuario se autentica correctamente.
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Lanza la autenticación automáticamente al mostrarse la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(appLockServiceProvider).authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Finanzas está bloqueada',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Usa tu huella o el PIN del teléfono',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _busy ? null : _authenticate,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open),
                label: const Text('Desbloquear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
