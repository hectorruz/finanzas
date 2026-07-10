import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/enums.dart';
import '../web_providers.dart';

/// Prefijo de indentación de árbol (·· por nivel) para los desplegables.
String _indent(int depth) => depth == 0 ? '' : '${'    ' * depth}└ ';

/// Desplegable de cuenta con jerarquía indentada (padres → subcuentas).
class WebAccountPicker extends ConsumerWidget {
  const WebAccountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Cuenta',
    this.excludeId,
    this.excludeIds = const {},
    this.includeNone = false,
    this.noneLabel = 'Sin cuenta',
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final String label;

  /// Cuenta a excluir (p. ej. la de origen en una transferencia).
  final int? excludeId;

  /// Conjunto de cuentas a excluir (p. ej. la propia cuenta y sus descendientes
  /// al elegir cuenta padre, para no crear ciclos).
  final Set<int> excludeIds;
  final bool includeNone;
  final String noneLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(webAccountTreeProvider);
    final rows = tree
        .where((r) => r.item.id != excludeId && !excludeIds.contains(r.item.id))
        .toList();
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (includeNone)
          DropdownMenuItem(value: null, child: Text(noneLabel)),
        for (final r in rows)
          DropdownMenuItem(
            value: r.item.id,
            child: Text(
              '${_indent(r.depth)}${r.item.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Desplegable de categoría (filtrado por tipo) con jerarquía indentada.
class WebCategoryPicker extends ConsumerWidget {
  const WebCategoryPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.kind,
    this.label = 'Categoría',
    this.includeNone = true,
    this.noneLabel = 'Sin categoría',
    this.excludeIds = const {},
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final CategoryKind kind;
  final String label;
  final bool includeNone;
  final String noneLabel;

  /// Categorías a excluir (p. ej. la propia y sus descendientes al elegir padre).
  final Set<int> excludeIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref
        .watch(kind == CategoryKind.expense
            ? webExpenseCategoryTreeProvider
            : webIncomeCategoryTreeProvider)
        .where((r) => !excludeIds.contains(r.item.id))
        .toList();
    // Si el valor actual no está en la lista filtrada (cambió el tipo), no lo
    // pasamos para que el desplegable no lance por un value inexistente.
    final ids = {for (final r in tree) r.item.id};
    final safeValue = (value != null && ids.contains(value)) ? value : null;
    return DropdownButtonFormField<int?>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (includeNone)
          DropdownMenuItem(value: null, child: Text(noneLabel)),
        for (final r in tree)
          DropdownMenuItem(
            value: r.item.id,
            child: Text(
              '${_indent(r.depth)}${r.item.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Pequeño chip-avatar coloreado usado en listas de cuentas/categorías/objetivos.
class WebColorDot extends StatelessWidget {
  const WebColorDot({super.key, required this.colorValue, this.icon, this.size = 36});
  final int colorValue;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon ?? Icons.circle, color: color, size: size * 0.55),
    );
  }
}

/// Ayuda para elegir un `IconData` a partir del nombre guardado (best-effort).
IconData webIconFor(String name, {IconData fallback = Icons.category}) {
  return kWebIconMap[name] ?? fallback;
}

/// Paleta de colores para los selectores de cuenta/categoría/objetivo.
const List<int> kWebColorPalette = [
  0xFF2196F3, 0xFF3F51B5, 0xFF009688, 0xFF4CAF50, 0xFF8BC34A,
  0xFFCDDC39, 0xFFFFC107, 0xFFFF9800, 0xFFFF5722, 0xFFF44336,
  0xFFE91E63, 0xFF9C27B0, 0xFF673AB7, 0xFF795548, 0xFF607D8B,
  0xFF9E9E9E,
];

const Map<String, IconData> kWebIconMap = {
  'account_balance': Icons.account_balance,
  'account_balance_wallet': Icons.account_balance_wallet,
  'savings': Icons.savings,
  'payments': Icons.payments,
  'credit_card': Icons.credit_card,
  'attach_money': Icons.attach_money,
  'euro': Icons.euro,
  'trending_up': Icons.trending_up,
  'shopping_cart': Icons.shopping_cart,
  'shopping_bag': Icons.shopping_bag,
  'restaurant': Icons.restaurant,
  'local_cafe': Icons.local_cafe,
  'local_grocery_store': Icons.local_grocery_store,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'directions_car': Icons.directions_car,
  'local_gas_station': Icons.local_gas_station,
  'directions_bus': Icons.directions_bus,
  'flight': Icons.flight,
  'medical_services': Icons.medical_services,
  'fitness_center': Icons.fitness_center,
  'school': Icons.school,
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'pets': Icons.pets,
  'card_giftcard': Icons.card_giftcard,
  'work': Icons.work,
  'category': Icons.category,
  'flag': Icons.flag,
  'star': Icons.star,
  'beach_access': Icons.beach_access,
};
