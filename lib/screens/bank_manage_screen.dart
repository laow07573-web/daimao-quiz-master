import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/question_bank.dart';
import 'import_screen.dart';

class BankManageScreen extends StatefulWidget {
  const BankManageScreen({super.key});

  @override
  State<BankManageScreen> createState() => _BankManageScreenState();
}

class _BankManageScreenState extends State<BankManageScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('题库管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          if (appState.banks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_books_outlined,
                      size: 64, color: cs.outlineVariant),
                  const SizedBox(height: 16),
                  Text('还没有题库',
                      style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('导入题库'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ImportScreen()),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildQuizSettings(appState, cs),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: appState.banks.length,
                  itemBuilder: (context, index) {
                    final bank = appState.banks[index];
                    final isSelected =
                        appState.selectedBankIds.contains(bank.id);
                    return _BankCard(
                      bank: bank,
                      isSelected: isSelected,
                      cs: cs,
                      onTap: () => appState.toggleBankSelection(bank.id!),
                      onDelete: () => _confirmDelete(context, appState, bank),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuizSettings(AppState appState, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: cs.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text('刷题设置',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
              const Spacer(),
              Text(
                appState.selectedBankIds.isEmpty
                    ? '点击题目前方选择框'
                    : '已选 ${appState.selectedBankIds.length} 个题库',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('刷题模式: ',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (appState.selectedBankIds.length > 1
                          ? cs.secondary
                          : cs.primary)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  appState.selectedBankIds.length > 1 ? '混合刷题' : '单题库刷题',
                  style: TextStyle(
                    fontSize: 13,
                    color: appState.selectedBankIds.length > 1
                        ? cs.secondary
                        : cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, AppState appState, QuestionBank bank) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除题库"${bank.name}"吗？\n该题库下的所有题目也将被删除，此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              appState.deleteBank(bank.id!);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  final QuestionBank bank;
  final bool isSelected;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BankCard({
    required this.bank,
    required this.isSelected,
    required this.cs,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? cs.primary : cs.outlineVariant,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 16, color: cs.onPrimary)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bank.name,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text('${bank.questionCount} 道题目',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: cs.onSurfaceVariant, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
