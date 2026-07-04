import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/models/enums.dart';
import '../../data/models/receipt.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../shared/widgets/amount_field.dart';
import '../../shared/widgets/entity_picker_field.dart';
import 'ocr_service.dart';

/// Captura una imagen de un ticket, ejecuta OCR y permite editar y guardar los
/// datos detectados (todo editable antes de confirmar).
class ReceiptScanScreen extends ConsumerStatefulWidget {
  const ReceiptScanScreen({super.key, this.autoStartCamera = false});

  /// Abre la cámara automáticamente al entrar (útil desde el acceso rápido:
  /// un toque hace la foto y luego se editan los detalles).
  final bool autoStartCamera;

  @override
  ConsumerState<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends ConsumerState<ReceiptScanScreen> {
  final _picker = ImagePicker();
  final _merchantController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.autoStartCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(ImageSource.camera);
      });
    }
  }

  String? _imagePath;
  bool _processing = false;
  String _rawText = '';
  int? _cents;
  DateTime _date = DateTime.now();
  int? _categoryId;
  String? _suggestedCategory;
  bool _createExpense = true;

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    setState(() {
      _imagePath = file.path;
      _processing = true;
    });
    try {
      final parsed = await ref.read(ocrServiceProvider).processImage(file.path);
      if (!mounted) return;
      setState(() {
        _rawText = parsed.rawText;
        _merchantController.text = parsed.merchant ?? '';
        _cents = parsed.totalCents;
        _date = parsed.date ?? DateTime.now();
        _suggestedCategory = parsed.suggestedCategory;
      });
      _applySuggestedCategory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo procesar la imagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _applySuggestedCategory() {
    if (_suggestedCategory == null) return;
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    for (final c in categories) {
      if (c.kind == CategoryKind.expense &&
          c.name.toLowerCase() == _suggestedCategory!.toLowerCase()) {
        setState(() => _categoryId = c.id);
        return;
      }
    }
  }

  Future<void> _save() async {
    if (_imagePath == null || _cents == null || _cents! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falta la imagen o el importe.')),
      );
      return;
    }

    int? transactionId;
    if (_createExpense) {
      final accounts = await ref.read(accountRepositoryProvider).all();
      final accountId = accounts.isNotEmpty ? accounts.first.id : null;
      if (accountId != null) {
        final txn = TransactionModel()
          ..type = TransactionType.expense
          ..amountCents = _cents!
          ..concept = _merchantController.text.trim()
          ..date = _date
          ..accountId = accountId
          ..categoryId = _categoryId;
        transactionId = await ref.read(transactionRepositoryProvider).save(txn);
      }
    }

    final receipt = Receipt()
      ..imagePath = _imagePath!
      ..merchant = _merchantController.text.trim()
      ..totalCents = _cents!
      ..date = _date
      ..rawText = _rawText
      ..categoryId = _categoryId
      ..transactionId = transactionId;
    await ref.read(receiptRepositoryProvider).save(receipt);

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) => c.kind == CategoryKind.expense)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Escanear ticket')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_imagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(_imagePath!), height: 200,
                  fit: BoxFit.cover, width: double.infinity),
            ),
          if (_processing) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('Reconociendo texto…')),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
          if (_imagePath != null) ...[
            const SizedBox(height: 20),
            Text('Datos detectados (editables)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Comercio',
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 16),
            AmountField(
              initialCents: _cents,
              label: 'Total',
              onChangedCents: (c) => _cents = c,
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha'),
              trailing:
                  Text(DateFormat('d MMM yyyy', 'es').format(_date)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 16),
            EntityPickerField(
              items: PickerItem.fromCategories(categories),
              value: _categoryId,
              onChanged: (v) => setState(() => _categoryId = v),
              labelText: 'Categoría',
              sheetTitle: 'Selecciona categoría',
              prefixIcon: Icons.category,
              allowNone: true,
              helperText: _suggestedCategory != null
                  ? 'Sugerida: $_suggestedCategory'
                  : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _createExpense,
              title: const Text('Crear gasto a partir del ticket'),
              onChanged: (v) => setState(() => _createExpense = v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar ticket'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
