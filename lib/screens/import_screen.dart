import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import 'import_preview_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<String> _selectedFiles = [];

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['doc', 'docx', 'json'], // v1.0.2: 支持 JSON 题库
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        _selectedFiles =
            result.files.where((f) => f.path != null).map((f) => f.path!).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // v1.0.2 设计审查修复：整页蓝白硬编码 → 主题色（此前切换任意主题都不变）
    final cs = Theme.of(context).colorScheme;
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('导入题库'),
        elevation: 0,
        backgroundColor: ac.navBar,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          final isProcessing =
              appState.importStatus.contains('解析中') || appState.importStatus.contains('提取');

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 流程说明
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: cs.onPrimary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI 智能解析',
                                style: TextStyle(
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              '自动提取题干、选项、答案，兼容各种 DOCX 格式',
                              style: TextStyle(
                                  color: cs.onPrimary.withOpacity(0.7),
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 格式说明
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ac.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ac.warning.withOpacity(0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: ac.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '支持 .docx 格式。解析后先预览题目，可编辑、删除后再确认入库。\n旧版 .doc 文件请先用 Word 另存为 .docx。',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 文件选择
                GestureDetector(
                  onTap: isProcessing ? null : _pickFiles,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: ac.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: ac.accent.withOpacity(0.3), width: 2),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('点击选择 DOCX 文件',
                            style: TextStyle(
                                fontSize: 16, color: ac.accent)),
                        const SizedBox(height: 4),
                        Text('AI 将自动识别题目、选项和答案',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        // v1.0.2 对齐里程碑：JSON 直导入库提示
                        Text('导入 .json 题库文件，无需 AI 解析，题目答案直接入库',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(
                            '选择本软件导出的 .json 题库文件（可多选）。导入完成后会显示导入报告。',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 已选文件
                if (_selectedFiles.isNotEmpty) ...[
                  Text('已选文件',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        final path = _selectedFiles[index];
                        // v1.0.2 设计审查修复：取文件名用 path 包 basename
                        final name = p.basename(path);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.description_outlined,
                                color: ac.accent),
                            title: Text(name,
                                style: const TextStyle(fontSize: 13)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: isProcessing
                                  ? null
                                  : () => setState(() =>
                                      _selectedFiles.removeAt(index)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 余额提示
                  if (appState.aiService?.cachedBalance != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Builder(
                        // v1.0.2 设计审查修复：getEstimatedRemainingQuestions
                        // 只调用一次（此前同一 build 调用两次）
                        builder: (ctx) {
                          final remaining =
                              appState.getEstimatedRemainingQuestions();
                          return Text(
                            '💰 余额 ¥${appState.aiService!.cachedBalance!.toStringAsFixed(2)}，预估可再导入 ${remaining > 0 ? "~$remaining 题" : "..."}',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          );
                        },
                      ),
                    ),

                  // 开始导入
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.auto_awesome, size: 20),
                      label: Text(
                        isProcessing ? 'AI 解析中...' : '开始 AI 导入',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ac.accent,
                        foregroundColor: ac.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isProcessing
                          ? null
                          : () async {
                              if (_selectedFiles.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('请先选择文件')),
                                );
                                return;
                              }
                              // v1.0.2: JSON 题库直接分组建库（无需预览）；
                              // 修复：解析失败展示真实错误，不再误报"导入完成 0 题"；
                              // 修复：与 docx 混选时 JSON 先入库，docx 继续走 AI 解析
                              final jsonFiles = _selectedFiles
                                  .where((f) =>
                                      f.toLowerCase().endsWith('.json'))
                                  .toList();
                              if (jsonFiles.isNotEmpty) {
                                final (banks, questions, err) =
                                    await appState.importJsonFiles(jsonFiles);
                                if (!mounted) return;
                                if (err != null && banks == 0 && questions == 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(err),
                                      backgroundColor: ac.warning,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'JSON 导入完成：$banks 个题库，$questions 道题'),
                                      backgroundColor: ac.success,
                                    ),
                                  );
                                }
                              }
                              final docxFiles = _selectedFiles
                                  .where((f) =>
                                      f.toLowerCase().endsWith('.docx') ||
                                      f.toLowerCase().endsWith('.doc'))
                                  .toList();
                              if (docxFiles.isEmpty) {
                                setState(() => _selectedFiles.clear());
                                return;
                              }
                              if (docxFiles.length > 1) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '已选择 ${docxFiles.length} 个文档，本次仅解析第一个'),
                                    backgroundColor: cs.onSurfaceVariant,
                                  ),
                                );
                              }
                              await appState.parseForPreview(docxFiles);
                              if (appState.previewQuestions.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text(appState.importStatus),
                                    backgroundColor: ac.warning,
                                  ),
                                );
                                return;
                              }
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ImportPreviewScreen()),
                              );
                            },
                    ),
                  ),

                  // 进度文字
                  if (isProcessing)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(appState.importStatus,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    ),
                ] else
                  const Spacer(),
              ],
            ),
          );
        },
      ),
    );
  }
}
