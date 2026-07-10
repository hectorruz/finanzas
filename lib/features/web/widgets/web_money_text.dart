import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../web_providers.dart';

/// Máscara que se muestra en lugar de un importe cuando el modo privacidad está
/// activo (equivalente web de `kHiddenAmount`).
const String kWebHiddenAmount = '••••';

/// Renderiza un importe respetando el modo privacidad (`webHideAmountsProvider`).
/// Preferir sobre `Text(Money(x).format())` para cualquier cifra en pantalla.
class WebMoneyText extends ConsumerWidget {
  const WebMoneyText(
    this.cents, {
    super.key,
    this.style,
    this.signed = false,
    this.color,
    this.textAlign,
  });

  final int cents;
  final TextStyle? style;

  /// Si es `true`, antepone `+`/`-` según el signo (para cifras de movimientos).
  final bool signed;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(webHideAmountsProvider);
    final base = Money(cents.abs()).format();
    final text = hide
        ? kWebHiddenAmount
        : signed
            ? '${cents < 0 ? '-' : cents > 0 ? '+' : ''}$base'
            : Money(cents).format();
    return Text(
      text,
      style: color != null ? (style ?? const TextStyle()).copyWith(color: color) : style,
      textAlign: textAlign,
    );
  }
}
