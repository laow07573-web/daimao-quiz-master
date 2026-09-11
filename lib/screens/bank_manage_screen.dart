import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_state.dart';
import '../services/bank_file_service.dart';
import '../models/question_bank.dart';
import '../utils/responsive.dart';
import 'import_screen.dart';

class BankManageScreen extends StatefulWidget {
  const BankManageScreen({super.key});

  @override
  State<BankManageScreen> createState() => _BankManageScreenState();
}

class _BankManageScreenState extends State<BankManageScreen> {
  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
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
      // 平板适配：内容限宽居中（手机无影响）
      body: ResponsivePage(
        child: Consumer<AppState>(
        builder: (context, appState, _) {
          if (appState.banks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_books_outlined,
                      size: 64, color: ac.border),
                  const SizedBox(height: 16),
                  Text('还没有题库',
                      style: TextStyle(fontSize: MaoType.h3, color: ac.textSecondary)),
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
              _buildQuizSettings(appState, ac),
              const Divider(height: 1),
              Expanded(
                // v1.0.3 宽屏重设计：宽屏题库卡 2 列网格，窄屏维持单列
                child: Builder(builder: (context) {
                  Widget buildCard(int index) {
                    final bank = appState.banks[index];
                    final isSelected =
                        appState.selectedBankIds.contains(bank.id);
                    return _BankCard(
                      bank: bank,
                      isSelected: isSelected,
                      onTap: () => appState.toggleBankSelection(bank.id!),
                      onDelete: () => _confirmDelete(context, appState, bank),
                      onExport: () => _exportBank(context, bank),
                    );
                  }

                  if (isWideLayout(context)) {
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 0,
                        childAspectRatio: 5.2,
                      ),
                      itemCount: appState.banks.length,
                      itemBuilder: (context, index) => buildCard(index),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: appState.banks.length,
                    itemBuilder: (context, index) => buildCard(index),
                  );
                }),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildQuizSettings(AppState appState, AppThemeColors ac) {
    final ac = AppThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      color: ac.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: ac.accent),
              const SizedBox(width: 6),
              Text('刷题设置',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: MaoType.h3, color: ac.textPrimary)),
              const Spacer(),
              Text(
                appState.selectedBankIds.isEmpty
                    ? '点击题目前方选择框'
                    : '已选 ${appState.selectedBankIds.length} 个题库',
                style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('刷题模式: ',
                  style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (appState.selectedBankIds.length > 1
                          ? ac.textSecondary
                          : ac.accent)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(MaoRadius.chip),
                ),
                child: Text(
                  appState.selectedBankIds.length > 1 ? '混合刷题' : '单题库刷题',
                  style: TextStyle(
                    fontSize: MaoType.body,
                    color: appState.selectedBankIds.length > 1
                        ? ac.textSecondary
                        : ac.accent,
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
    final ac = AppThemeColors.of(context);
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
            style: TextButton.styleFrom(foregroundColor: ac.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// v1.0.2 扩展：导出题库（含打标签/解析的整理后字段）为 .json 并分享
  Future<void> _exportBank(BuildContext context, QuestionBank bank) async {
    final dir = Directory.systemTemp.createTempSync('bank_export');
    final path =
        '${dir.path}/${bank.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.json';
    final result = await BankFileService.exportBank(bank.id!, bank.name, path);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该题库没有题目，无法导出')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导出 ${bank.questionCount} 道题目为 .json 文件'),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
        duration: const Duration(seconds: 3),
      ),
    );
    try {
      await Share.shareXFiles([XFile(result)], subject: '猫卷题库导出');
    } catch (e) {
      // v1.0.2 设计审查修复：分享失败不再静默
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }
}

class _BankCard extends StatelessWidget {
  final QuestionBank bank;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _BankCard({
    required this.bank,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ac.surfaceAlt,
          borderRadius: BorderRadius.circular(MaoRadius.small),
          border: Border.all(
            color: isSelected ? ac.accent : ac.border,
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
                  color: isSelected ? ac.accent : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? ac.accent : ac.border,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(MaoRadius.chip),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 16, color: ac.onAccent)
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
                          fontSize: MaoType.h3, fontWeight: FontWeight.w600, color: ac.textPrimary)),
                  const SizedBox(height: 4),
                  Text('${bank.questionCount} 道题目',
                      style: TextStyle(
                          fontSize: MaoType.body, color: ac.textSecondary)),
                ],
              ),
            ),
            IconButton(
              tooltip: '导出题库',
              icon: Icon(Icons.file_download_outlined,
                  color: ac.textSecondary, size: 20),
              onPressed: onExport,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: ac.textSecondary, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
