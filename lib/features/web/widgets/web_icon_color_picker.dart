import 'package:flutter/material.dart';

import 'web_pickers.dart';

/// Selector compacto de color + icono para cuentas/categorías/objetivos.
class WebIconColorPicker extends StatelessWidget {
  const WebIconColorPicker({
    super.key,
    required this.colorValue,
    required this.iconName,
    required this.onColor,
    required this.onIcon,
  });

  final int colorValue;
  final String iconName;
  final ValueChanged<int> onColor;
  final ValueChanged<String> onIcon;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Color', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in kWebColorPalette)
              InkWell(
                onTap: () => onColor(c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c == colorValue
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: c == colorValue
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Icono', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        SizedBox(
          height: 132,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in kWebIconMap.entries)
                  InkWell(
                    onTap: () => onIcon(entry.key),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: entry.key == iconName
                            ? color.withValues(alpha: 0.2)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: entry.key == iconName
                              ? color
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(entry.value,
                          size: 20,
                          color: entry.key == iconName
                              ? color
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
