import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/money/money.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/account_repository.dart';
import '../../shared/widgets/async_value_view.dart';

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
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final a = list[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(a.colorValue).withOpacity(0.18),
                  child: Icon(iconByName(a.iconName),
                      color: Color(a.colorValue)),
                ),
                title: Text(a.name),
                subtitle: Text(_typeLabel(a.type.name)),
                trailing: Consumer(
                  builder: (context, ref, _) {
                    final balance = ref.watch(accountBalanceProvider(a.id));
                    return balance.maybeWhen(
                      data: (c) => Text(
                        Money(c).format(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      orElse: () => const Text('…'),
                    );
                  },
                ),
                onTap: () =>
                    context.push(Routes.accountEditor, extra: a.id),
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
        _ => type,
      };
}
