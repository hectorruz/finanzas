import 'package:flutter/material.dart';

import '../../core/icons/app_icons.dart';

/// Paleta de colores predefinidos para cuentas, categorías y objetivos.
const List<int> kPaletteColors = [
  0xFF1976D2, 0xFF388E3C, 0xFFEF5350, 0xFFAB47BC, 0xFFFF7043,
  0xFF26A69A, 0xFF5C6BC0, 0xFFFFA000, 0xFF8D6E63, 0xFF78909C,
  0xFFEC407A, 0xFF26C6DA, 0xFF9CCC65, 0xFF42A5F5, 0xFF66BB6A,
];

/// Selector compacto de icono y color.
class IconColorPicker extends StatelessWidget {
  const IconColorPicker({
    super.key,
    required this.iconName,
    required this.colorValue,
    required this.onIconChanged,
    required this.onColorChanged,
  });

  final String iconName;
  final int colorValue;
  final ValueChanged<String> onIconChanged;
  final ValueChanged<int> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Icono', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final name in kAppIconNames)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: name == iconName,
                    label: Icon(iconByName(name)),
                    onSelected: (_) => onIconChanged(name),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in kPaletteColors)
              GestureDetector(
                onTap: () => onColorChanged(color),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == colorValue
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: color == colorValue
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 20)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
