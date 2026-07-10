import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/enums.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_icon_color_picker.dart';
import '../widgets/web_pickers.dart';

/// Alta/edición de una categoría. El `kind` (gasto/ingreso) lo fija el panel de
/// origen; las subcategorías heredan el tipo del padre.
class WebCategoryDialog extends ConsumerStatefulWidget {
  const WebCategoryDialog({
    super.key,
    this.existing,
    required this.kind,
    this.parentId,
  });
  final CategoryDto? existing;
  final CategoryKind kind;
  final int? parentId;

  @override
  ConsumerState<WebCategoryDialog> createState() => _WebCategoryDialogState();
}

class _WebCategoryDialogState extends ConsumerState<WebCategoryDialog> {
  late final TextEditingController _name;
  int? _parentId;
  late int _color;
  late String _icon;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _parentId = e?.parentId ?? widget.parentId;
    _color = e?.colorValue ?? 0xFF9E9E9E;
    _icon = e?.iconName ?? 'category';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pon un nombre');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final dto = CategoryDto(
      name: name,
      kind: widget.kind,
      parentId: _parentId,
      colorValue: _color,
      iconName: _icon,
      isDefault: widget.existing?.isDefault ?? false,
      sortOrder: widget.existing?.sortOrder ?? 0,
    );
    final client = ref.read(webClientProvider)!;
    try {
      if (widget.existing != null) {
        await client.updateCategory(widget.existing!.id, dto);
      } else {
        await client.createCategory(dto);
      }
      bumpWebRefresh(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar categoría'),
        content: Text('¿Borrar "${e.name}" y sus subcategorías?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(webClientProvider)!.deleteCategory(e.id);
    bumpWebRefresh(ref);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(webCategoriesProvider).valueOrNull ?? const [];
    final sameKind = all.where((c) => c.kind == widget.kind).toList();
    final exclude = widget.existing == null
        ? <int>{}
        : {
            widget.existing!.id,
            ...webDescendantIds(widget.existing!.id, sameKind),
          };

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.existing == null
                        ? 'Nueva categoría'
                        : 'Editar categoría',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Chip(
                    label: Text(widget.kind == CategoryKind.expense
                        ? 'Gasto'
                        : 'Ingreso'),
                  ),
                  if (widget.existing != null)
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy ? null : _delete),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 14),
              WebCategoryPicker(
                label: 'Categoría padre (opcional)',
                value: _parentId,
                kind: widget.kind,
                includeNone: true,
                noneLabel: 'Ninguna (categoría principal)',
                excludeIds: exclude,
                onChanged: (v) => setState(() => _parentId = v),
              ),
              const SizedBox(height: 16),
              WebIconColorPicker(
                colorValue: _color,
                iconName: _icon,
                onColor: (c) => setState(() => _color = c),
                onIcon: (i) => setState(() => _icon = i),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Guardando…' : 'Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
