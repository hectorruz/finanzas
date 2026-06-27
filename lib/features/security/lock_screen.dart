import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import 'app_lock_service.dart';

/// Pantalla a pantalla completa que cubre la app mientras está bloqueada.
/// Pide PIN (siempre) y ofrece biometría si el usuario la activó.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  /// Se invoca cuando el usuario se autentica correctamente.
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const _pinLength = 4;

  String _pin = '';
  bool _error = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Lanza la biometría automáticamente al mostrarse, si está activada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(currentSettingsProvider);
      if (settings.biometricUnlock) _tryBiometric();
    });
  }

  Future<void> _tryBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(appLockServiceProvider).authenticateBiometric();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onUnlocked();
  }

  void _onDigit(String d) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == _pinLength) _submit();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    final settings = ref.read(currentSettingsProvider);
    final ok = ref.read(appLockServiceProvider).verifyPin(settings, _pin);
    if (ok) {
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(currentSettingsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.lock_outline,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Introduce tu PIN',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            _PinDots(
              length: _pinLength,
              filled: _pin.length,
              error: _error,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 20,
              child: _error
                  ? Text('PIN incorrecto',
                      style: TextStyle(color: theme.colorScheme.error))
                  : null,
            ),
            const Spacer(),
            _Keypad(
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              onBiometric: settings.biometricUnlock ? _tryBiometric : null,
              busy: _busy,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.error,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = error ? scheme.error : scheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? active : Colors.transparent,
              border: Border.all(color: active, width: 2),
            ),
          ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
    required this.busy,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _KeypadButton(
          onTap: () => onDigit(d),
          child: Text(d,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w500)),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [digit('1'), digit('2'), digit('3')]),
          Row(children: [digit('4'), digit('5'), digit('6')]),
          Row(children: [digit('7'), digit('8'), digit('9')]),
          Row(
            children: [
              _KeypadButton(
                onTap: onBiometric,
                child: onBiometric == null
                    ? const SizedBox.shrink()
                    : busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint, size: 30),
              ),
              digit('0'),
              _KeypadButton(
                onTap: onBackspace,
                child: const Icon(Icons.backspace_outlined, size: 26),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.6,
        child: InkResponse(
          onTap: onTap,
          radius: 44,
          child: Center(child: child),
        ),
      ),
    );
  }
}
