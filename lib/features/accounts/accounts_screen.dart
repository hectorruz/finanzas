import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/account_repository.dart';
import '../../shared/widgets/async_value_view.dart';
import '../../shared/widgets/money_text.dart';
import 'account_editor_screen.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.accountEditor),
        icon: const Icon(Icons.add),
        label: const Text('Nueva cuenta'),
      ),
      body: AsyncValueView(
        value: accounts,
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No hay cuentas.'));
          }
          final entries = flattenAccounts(list);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final entry = entries[i];
              final a = entry.value;
              final isRoot = entry.depth == 0;
              return Padding(
                padding: EdgeInsets.only(left: entry.depth * 24.0),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: isRoot ? 20 : 16,
                    backgroundColor: Color(a.colorValue).withOpacity(0.18),
                    child: Icon(iconByName(a.iconName),
                        size: isRoot ? 24 : 18, color: Color(a.colorValue)),
                  ),
                  title: Text(a.name),
                  subtitle: Text(a.note.isNotEmpty
                      ? '${_typeLabel(a.type.name)} · ${a.note}'
                      : _typeLabel(a.type.name)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Añadir subcuenta',
                        icon: const Icon(Icons.add),
                        onPressed: () => context.push(
                          Routes.accountEditor,
                          extra: AccountEditorArgs(parentId: a.id),
                        ),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final balance =
                              ref.watch(accountBalanceProvider(a.id));
                          return balance.maybeWhen(
                            data: (c) => MoneyText(
                              c,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            orElse: () => const Text('…'),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () => context.push(Routes.accountEditor, extra: a.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
        'bank' => 'Banco',
        'cash' => 'Efectivo',
        'investment' => 'Inversiones',
        _ => type,
      };
}
