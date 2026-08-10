import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_state.dart';
import '../services/bank_file_service.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('导入题库'),
        elevation: 0,
        backgroundColor: const Color(0xFF4A90D9),
        foregroundColor: Colors.white,
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A90D9), Color(0xFF357ABD)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI 智能解析',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            SizedBox(height: 4),
                            Text(
                              '自动提取题干、选项、答案，兼容各种 DOCX 格式',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
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
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.orange[800]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '支持 .docx 格式。解析后先预览题目，可编辑、删除后再确认入库。\n旧版 .doc 文件请先用 Word 另存为 .docx。',
                          style: TextStyle(
                              fontSize: 12, color: Colors.brown[700]),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF4A90D9).withOpacity(0.3),
                          width: 2),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        const Text('点击选择 DOCX 文件',
                            style: TextStyle(
                                fontSize: 16, color: Color(0xFF4A90D9))),
                        const SizedBox(height: 4),
                        const Text('AI 将自动识别题目、选项和答案',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF999999))),
                        const SizedBox(height: 4),
                        // v1.0.2 对齐里程碑：JSON 直导入库提示
                        const Text('导入 .json 题库文件，无需 AI 解析，题目答案直接入库',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF999999))),
                        const SizedBox(height: 4),
                        const Text(
                            '选择本软件导出的 .json 题库文件（可多选）。导入完成后会显示导入报告。',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF999999))),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 已选文件
                if (_selectedFiles.isNotEmpty) ...[
                  const Text('已选文件',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        final path = _selectedFiles[index];
                        final name =
                            path.split('/').last.split('\\').last;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.description_outlined,
                                color: Color(0xFF4A90D9)),
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
                      child: Text(
                        '💰 余额 ¥${appState.aiService!.cachedBalance!.toStringAsFixed(2)}，预估可再导入 ${appState.getEstimatedRemainingQuestions() > 0 ? "~${appState.getEstimatedRemainingQuestions()} 题" : "..."}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                              child:
                                  CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                            )
                          : const Icon(Icons.auto_awesome, size: 20),
                      label: Text(
                        isProcessing ? 'AI 解析中...' : '开始 AI 导入',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90D9),
                        foregroundColor: Colors.white,
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
                                final (banks, questions) =
                                    await appState.importJsonFiles(jsonFiles);
                                final err = BankFileService.lastError;
                                if (!mounted) return;
                                if (err != null && banks == 0 && questions == 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(err),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'JSON 导入完成：$banks 个题库，$questions 道题'),
                                      backgroundColor:
                                          const Color(0xFF4CAF50),
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
                                    backgroundColor:
                                        Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    backgroundColor: appState.importStatus
                                                .contains('完成')
                                            ? null
                                            : Colors.orange,
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
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF666666))),
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
