import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../data/repositories/settings_repository.dart';

/// `true` si el modo privacidad (ocultar importes) está activo.
final hideAmountsProvider = Provider<bool>(
  (ref) => ref.watch(currentSettingsProvider).hideAmounts,
);

/// Marcador usado cuando los importes están ocultos.
const kHiddenAmount = '••••';

/// Texto de un importe que respeta el modo privacidad. Si está activo, muestra
/// un marcador en lugar de la cantidad.
class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.signed = false,
    this.prefix = '',
    this.style,
    this.textAlign,
  });

  final int cents;
  final bool signed;
  final String prefix;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(hideAmountsProvider);
    final text = hide
        ? kHiddenAmount
        : '$prefix${signed ? Money(cents).formatSigned() : Money(cents).format()}';
    return Text(text, style: style, textAlign: textAlign);
  }
}
