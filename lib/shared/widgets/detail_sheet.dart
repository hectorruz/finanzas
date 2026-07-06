import 'package:flutter/material.dart';

/// Muestra un panel de detalles estilo apps de banco: se desliza desde abajo,
/// ocupa como mucho media pantalla (se puede arrastrar hacia arriba para ver
/// todo o hacia abajo para cerrarlo) y oscurece el fondo (barrera modal).
///
/// [builder] recibe el `ScrollController` del `DraggableScrollableSheet`, que
/// debe conectarse al scroll interno para que el gesto de arrastre funcione.
Future<T?> showDetailSheet<T>(
  BuildContext context, {
  required Widget Function(ScrollController controller) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => builder(controller),
    ),
  );
}

/// Fila de detalle: icono + etiqueta + valor. Usada dentro de los paneles.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueWidget,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                valueWidget ??
                    Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
