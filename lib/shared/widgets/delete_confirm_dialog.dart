import 'package:flutter/material.dart';

/// Resultado de un diálogo de confirmación de borrado.
class DeleteConfirmResult {
  const DeleteConfirmResult({
    required this.confirmed,
    required this.alsoDeleteLinked,
  });

  final bool confirmed;

  /// Si el usuario quiere borrar también el/los elemento(s) vinculado(s)
  /// (p. ej. el gasto creado a partir de un ticket).
  final bool alsoDeleteLinked;
}

/// Muestra un diálogo de confirmación de borrado. Si [hasLinked] es true,
/// incluye una casilla "Borrar también…" marcada por defecto.
///
/// Devuelve `null` si se cancela.
Future<DeleteConfirmResult?> showDeleteConfirm(
  BuildContext context, {
  required String title,
  required String message,
  bool hasLinked = false,
  String linkedLabel = 'Borrar también el gasto vinculado',
}) {
  return showDialog<DeleteConfirmResult>(
    context: context,
    builder: (context) {
      var alsoDelete = true;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (hasLinked) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: alsoDelete,
                    title: Text(linkedLabel),
                    onChanged: (v) => setState(() => alsoDelete = v ?? false),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  DeleteConfirmResult(
                    confirmed: true,
                    alsoDeleteLinked: hasLinked && alsoDelete,
                  ),
                ),
                child: const Text('Eliminar'),
              ),
            ],
          );
        },
      );
    },
  );
}
