import 'package:flutter/material.dart';

import '../../core/icons/app_icons.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/repositories/tree.dart';

/// Un elemento seleccionable en [EntityPickerField], desacoplado de los modelos
/// Isar. Puede formar parte de una jerarquía padre/hijo de anidamiento ilimitado.
class PickerItem {
  const PickerItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.parentId,
  });

  final int id;
  final String name;
  final IconData icon;
  final Color color;
  final int? parentId;

  /// Construye la lista de ítems a partir de una lista de cuentas.
  static List<PickerItem> fromAccounts(Iterable<Account> accounts) => [
        for (final a in accounts)
          PickerItem(
            id: a.id,
            name: a.name,
            icon: iconByName(a.iconName),
            color: Color(a.colorValue),
            parentId: a.parentId,
          ),
      ];

  /// Construye la lista de ítems a partir de una lista de categorías.
  static List<PickerItem> fromCategories(Iterable<Category> categories) => [
        for (final c in categories)
          PickerItem(
            id: c.id,
            name: c.name,
            icon: iconByName(c.iconName),
            color: Color(c.colorValue),
            parentId: c.parentId,
          ),
      ];
}

/// Ruta completa de un ítem dentro de su jerarquía, p. ej. `Alimentación · Casa`
/// para una subcategoría, de modo que el valor seleccionado no sea ambiguo.
String _qualifiedName(PickerItem item, List<PickerItem> items) {
  final byId = {for (final i in items) i.id: i};
  final parts = <String>[item.name];
  var parentId = item.parentId;
  final seen = <int>{item.id};
  while (parentId != null && seen.add(parentId)) {
    final parent = byId[parentId];
    if (parent == null) break;
    parts.add(parent.name);
    parentId = parent.parentId;
  }
  return parts.reversed.join(' · ');
}

/// Campo de formulario que abre una hoja inferior modal (estilo nativo Android)
/// para elegir una cuenta o categoría dentro de una jerarquía plegable, con
/// búsqueda. Sustituye al desplegable `DropdownButtonFormField`.
///
/// Es un [FormField] para conservar la validación (p. ej. cuenta obligatoria).
class EntityPickerField extends FormField<int?> {
  EntityPickerField({
    super.key,
    required List<PickerItem> items,
    required int? value,
    required ValueChanged<int?> onChanged,
    required String labelText,
    required String sheetTitle,
    IconData? prefixIcon,
    String? helperText,
    bool allowNone = false,
    String noneLabel = 'Sin categoría',
    super.validator,
  }) : super(
          initialValue: value,
          builder: (state) {
            final context = state.context;
            final theme = Theme.of(context);
            // El id existe entre los ítems disponibles (puede haberse filtrado
            // al cambiar de tipo, igual que hacía el desplegable anterior).
            PickerItem? selected;
            if (value != null) {
              for (final i in items) {
                if (i.id == value) {
                  selected = i;
                  break;
                }
              }
            }
            final selectedLabel =
                selected == null ? null : _qualifiedName(selected, items);

            Future<void> open() async {
              final result = await showModalBottomSheet<_PickerResult>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => _PickerSheet(
                  items: items,
                  selectedId: value,
                  title: sheetTitle,
                  allowNone: allowNone,
                  noneLabel: noneLabel,
                ),
              );
              if (result == null) return; // Cerrada sin elegir.
              state.didChange(result.id);
              onChanged(result.id);
            }

            return InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: open,
              child: InputDecorator(
                isEmpty: false,
                decoration: InputDecoration(
                  labelText: labelText,
                  prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
                  helperText: helperText,
                  errorText: state.errorText,
                ),
                child: Row(
                  children: [
                    if (selected != null) ...[
                      Icon(selected.icon, size: 20, color: selected.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selectedLabel ?? selected.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Text(
                          allowNone ? noneLabel : '',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Icon(Icons.arrow_drop_down,
                        color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            );
          },
        );
}

/// Resultado devuelto por la hoja: envuelve el id para distinguir "no eligió
/// nada" (Navigator.pop sin valor -> null) de "eligió Sin categoría" (id null).
class _PickerResult {
  const _PickerResult(this.id);
  final int? id;
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.items,
    required this.selectedId,
    required this.title,
    required this.allowNone,
    required this.noneLabel,
  });

  final List<PickerItem> items;
  final int? selectedId;
  final String title;
  final bool allowNone;
  final String noneLabel;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Ids de nodos expandidos en la vista de árbol.
  final Set<int> _expanded = {};

  /// Hijos directos por id de padre (null = primer nivel).
  late final Map<int?, List<PickerItem>> _childrenByParent;

  @override
  void initState() {
    super.initState();
    final ids = widget.items.map((i) => i.id).toSet();
    _childrenByParent = {};
    for (final item in widget.items) {
      final parent =
          (item.parentId != null && ids.contains(item.parentId))
              ? item.parentId
              : null;
      _childrenByParent.putIfAbsent(parent, () => []).add(item);
    }
    // Expandir la rama del ítem seleccionado para que quede visible.
    var current = widget.selectedId;
    final byId = {for (final i in widget.items) i.id: i};
    while (current != null) {
      final item = byId[current];
      final parent = item?.parentId;
      if (parent != null && ids.contains(parent)) _expanded.add(parent);
      current = parent;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Normaliza a minúsculas y sin diacríticos para la búsqueda.
  String _normalize(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    var out = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out;
  }

  bool _hasChildren(int id) => _childrenByParent.containsKey(id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _normalize(_query.trim());

    // Filas a renderizar: (item, profundidad). item == null => "Sin categoría".
    final rows = <_PickerRow>[];
    if (widget.allowNone && query.isEmpty) {
      rows.add(const _PickerRow(null, 0));
    }

    if (query.isEmpty) {
      // Vista de árbol plegable.
      void addLevel(int? parent, int depth) {
        for (final item in _childrenByParent[parent] ?? const []) {
          rows.add(_PickerRow(item, depth));
          if (_hasChildren(item.id) && _expanded.contains(item.id)) {
            addLevel(item.id, depth + 1);
          }
        }
      }

      addLevel(null, 0);
    } else {
      // Búsqueda: lista plana con todas las coincidencias, en orden de árbol.
      final flat = flattenTree<PickerItem>(
        widget.items,
        idOf: (i) => i.id,
        parentIdOf: (i) => i.parentId,
      );
      for (final e in flat) {
        if (_normalize(e.value.name).contains(query)) {
          rows.add(_PickerRow(e.value, 0));
        }
      }
    }

    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.title,
                      style: theme.textTheme.titleLarge),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text('Sin resultados',
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding:
                            EdgeInsets.only(bottom: media.padding.bottom),
                        itemCount: rows.length,
                        itemBuilder: (context, index) =>
                            _buildRow(rows[index], theme),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(_PickerRow row, ThemeData theme) {
    // Fila "Sin categoría".
    if (row.item == null) {
      final selected = widget.selectedId == null;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor:
              theme.colorScheme.surfaceContainerHighest,
          child: Icon(Icons.block,
              color: theme.colorScheme.onSurfaceVariant),
        ),
        title: Text(widget.noneLabel),
        selected: selected,
        trailing: selected ? const Icon(Icons.check) : null,
        onTap: () => Navigator.of(context).pop(const _PickerResult(null)),
      );
    }

    final item = row.item!;
    final selected = widget.selectedId == item.id;
    final hasChildren = _hasChildren(item.id);
    final expanded = _expanded.contains(item.id);

    return ListTile(
      contentPadding: EdgeInsets.only(left: 16.0 + row.depth * 24, right: 8),
      leading: CircleAvatar(
        backgroundColor: item.color.withValues(alpha: 0.15),
        child: Icon(item.icon, color: item.color),
      ),
      title: Text(item.name, overflow: TextOverflow.ellipsis),
      selected: selected,
      trailing: hasChildren
          ? IconButton(
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() {
                if (expanded) {
                  _expanded.remove(item.id);
                } else {
                  _expanded.add(item.id);
                }
              }),
            )
          : (selected ? const Icon(Icons.check) : null),
      onTap: () => Navigator.of(context).pop(_PickerResult(item.id)),
    );
  }
}

/// Una fila a renderizar en la hoja: el ítem (null = "Sin categoría") y su
/// profundidad en el árbol.
class _PickerRow {
  const _PickerRow(this.item, this.depth);
  final PickerItem? item;
  final int depth;
}
