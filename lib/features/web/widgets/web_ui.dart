import 'package:flutter/material.dart';

/// Ancho máximo del área de contenido en pantallas muy anchas (legibilidad).
const double kWebContentMaxWidth = 1200;

/// Estructura común de una página de escritorio: cabecera con título + acciones
/// y un cuerpo centrado con ancho máximo. Evita que el contenido se estire de
/// borde a borde en monitores anchos (que es lo que hace parecer "app móvil").
class WebPage extends StatelessWidget {
  const WebPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.maxWidth = kWebContentMaxWidth,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 28),
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 20),
        child,
      ],
    );

    final constrained = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: content),
      ),
    );

    return scrollable
        ? SingleChildScrollView(child: constrained)
        : constrained;
  }
}

/// Tarjeta contenedora estándar (superficie elevada con borde redondeado).
class WebCard extends StatelessWidget {
  const WebCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Tarjeta de KPI (etiqueta + valor grande + delta opcional).
class WebKpiCard extends StatelessWidget {
  const WebKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final Widget value;
  final IconData? icon;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.outline)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
            child: value,
          ),
        ],
      ),
    );
  }
}

/// Estado vacío centrado con icono, título y mensaje.
class WebEmptyState extends StatelessWidget {
  const WebEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder de sección aún no implementada (durante el desarrollo por fases).
class WebComingSoon extends StatelessWidget {
  const WebComingSoon({super.key, required this.title, this.icon = Icons.construction});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return WebPage(
      title: title,
      child: const WebEmptyState(
        icon: Icons.construction,
        title: 'En construcción',
        message: 'Esta sección llega en una fase próxima de la webapp.',
      ),
    );
  }
}
