import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../dialogs/web_receipt_dialog.dart';
import '../web_models.dart';
import '../web_providers.dart';
import '../widgets/web_money_text.dart';
import '../widgets/web_ui.dart';

/// Tickets: galería con miniaturas (imágenes servidas por el móvil), subida de
/// foto → OCR en el móvil → revisión → guardado (con gasto vinculado opcional).
class WebReceiptsPage extends ConsumerStatefulWidget {
  const WebReceiptsPage({super.key});

  @override
  ConsumerState<WebReceiptsPage> createState() => _WebReceiptsPageState();
}

class _WebReceiptsPageState extends ConsumerState<WebReceiptsPage> {
  bool _ocrBusy = false;

  Future<void> _upload() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = (file.extension != null && file.extension!.isNotEmpty)
        ? '.${file.extension}'
        : '.jpg';
    setState(() => _ocrBusy = true);
    try {
      final parsed =
          await ref.read(webClientProvider)!.ocr(bytes, imageExt: ext);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) =>
            WebReceiptDialog(parsed: parsed, imageBytes: bytes, imageExt: ext),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error de OCR: $e')));
      }
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiptsAsync = ref.watch(webReceiptsProvider);

    return WebPage(
      title: 'Tickets',
      actions: [
        IconButton(
          tooltip: 'Refrescar',
          icon: const Icon(Icons.refresh),
          onPressed: () => bumpWebRefresh(ref),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: _ocrBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(_ocrBusy ? 'Procesando…' : 'Subir ticket'),
          onPressed: _ocrBusy ? null : _upload,
        ),
      ],
      child: receiptsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Error: $e'),
        data: (receipts) {
          if (receipts.isEmpty) {
            return WebEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Sin tickets',
              message:
                  'Sube una foto de un ticket: el móvil la lee con OCR y tú revisas.',
              action: FilledButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Subir ticket'),
                onPressed: _ocrBusy ? null : _upload,
              ),
            );
          }
          return LayoutBuilder(builder: (context, constraints) {
            final cols = (constraints.maxWidth / 240).floor().clamp(1, 6);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.82,
              children: [
                for (final r in receipts) _ReceiptCard(receipt: r),
              ],
            );
          });
        },
      ),
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  const _ReceiptCard({required this.receipt});
  final ReceiptDto receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebCard(
      padding: EdgeInsets.zero,
      onTap: () => showDialog(
          context: context,
          builder: (_) => _ReceiptDetailDialog(receipt: receipt)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _Thumb(receipt: receipt)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.merchant.isEmpty ? 'Ticket' : receipt.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd/MM/yy').format(receipt.date),
                        style: Theme.of(context).textTheme.bodySmall),
                    WebMoneyText(receipt.totalCents,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.receipt});
  final ReceiptDto receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (!receipt.hasImage) {
      return Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.receipt_long,
            size: 48, color: scheme.outlineVariant),
      );
    }
    final bytes = ref.watch(webReceiptImageProvider(receipt.id));
    return bytes.when(
      loading: () => Container(
        color: scheme.surfaceContainerHighest,
        child: const Center(
            child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: scheme.outlineVariant),
      ),
      data: (data) => data.isEmpty
          ? Container(color: scheme.surfaceContainerHighest)
          : Image.memory(data, fit: BoxFit.cover),
    );
  }
}

class _ReceiptDetailDialog extends ConsumerWidget {
  const _ReceiptDetailDialog({required this.receipt});
  final ReceiptDto receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(webCategoriesByIdProvider);
    final accounts = ref.watch(webAccountsByIdProvider);
    final cat = receipt.categoryId != null ? categories[receipt.categoryId] : null;
    final acc = receipt.accountId != null ? accounts[receipt.accountId] : null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        receipt.merchant.isEmpty ? 'Ticket' : receipt.merchant,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  WebMoneyText(receipt.totalCents,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              if (receipt.hasImage)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _FullImage(id: receipt.id),
                  ),
                ),
              const SizedBox(height: 12),
              _row(context, Icons.event, 'Fecha',
                  DateFormat('d MMM yyyy', 'es').format(receipt.date)),
              _row(context, Icons.category, 'Categoría', cat?.name ?? '—'),
              _row(context, Icons.account_balance, 'Cuenta', acc?.name ?? '—'),
              _row(context, Icons.link, 'Gasto vinculado',
                  receipt.transactionId != null ? 'Sí' : 'No'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Borrar'),
                    onPressed: () => _delete(context, ref),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(
                          context: context,
                          builder: (_) => WebReceiptDialog(existing: receipt));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    var withExpense = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Borrar ticket'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Borrar este ticket?'),
              if (receipt.transactionId != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: withExpense,
                  title: const Text('Borrar también el gasto vinculado'),
                  onChanged: (v) => setState(() => withExpense = v ?? false),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Borrar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref
        .read(webClientProvider)!
        .deleteReceipt(receipt.id, withExpense: withExpense);
    bumpWebRefresh(ref);
    if (context.mounted) Navigator.pop(context);
  }
}

class _FullImage extends ConsumerWidget {
  const _FullImage({required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(webReceiptImageProvider(id));
    return bytes.when(
      loading: () => const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(
          height: 120, child: Center(child: Icon(Icons.broken_image))),
      data: (data) => data.isEmpty
          ? const SizedBox(height: 120)
          : Image.memory(data, fit: BoxFit.contain),
    );
  }
}
