import '../utils/design_tokens.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/responsive.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<String> _selectedFiles = [];

  /// v1.27 后台导入：示例题库任务交给应用层，立即回首页（进度在首页展示，
  /// 完成后弹提示），不再阻塞在导入页。
  void _importSample() {
    final appState = context.read<AppState>();
    if (appState.importTaskActive) return;
    unawaited(appState.startBackgroundSampleImport());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已开始导入示例题库，进度见首页')),
    );
    Navigator.pop(context);
  }

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
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(
        title: const Text('导入题库'),
        elevation: 0,
        backgroundColor: ac.navBar,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          // v1.27 后台导入：任务状态改用应用层标志（进度精确展示，离开页面不中断）
          final isProcessing = appState.importTaskActive;

          // 平板适配：内容限宽居中（手机无影响）。
          // v1.27 修复：整页改单滚动结构——此前文件列表被压在 Column 的
          // Expanded 里，上方固定内容占满小窗口/手机屏时列表区几乎为 0，
          // 无法滚动查看已选文件名；现在整页可滚动，操作按钮固定在页底。
          return ResponsivePage(
            child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 流程说明
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [ac.accent, ac.accent.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(MaoRadius.control),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: ac.onAccent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI 智能解析',
                                style: TextStyle(
                                    color: ac.onAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: MaoType.h3)),
                            const SizedBox(height: 4),
                            Text(
                              '自动提取题干、选项、答案，兼容各种 DOCX 格式',
                              style: TextStyle(
                                  color: ac.onAccent.withOpacity(0.7),
                                  fontSize: MaoType.caption),
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
                    borderRadius: BorderRadius.circular(MaoRadius.small),
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
                              fontSize: MaoType.body, color: ac.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 一键导入内置示例题库（新用户/演示：无需文件立即体验刷题）
                GestureDetector(
                  onTap: isProcessing ? null : _importSample,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: ac.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(MaoRadius.control),
                      border:
                          Border.all(color: ac.accent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.rocket_launch_outlined,
                            color: ac.accent, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('一键导入示例题库',
                                  style: TextStyle(
                                      fontSize: MaoType.h3,
                                      fontWeight: FontWeight.w600,
                                      color: ac.accent)),
                              const SizedBox(height: 2),
                              Text(
                                  '内置 10 道医学示例题（单选/多选/判断），无需文件立即体验',
                                  style: TextStyle(
                                      fontSize: MaoType.body,
                                      color: ac.textSecondary)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: ac.accent),
                      ],
                    ),
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
                      borderRadius: BorderRadius.circular(MaoRadius.control),
                      border: Border.all(
                          color: ac.accent.withOpacity(0.3), width: 2),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 48, color: ac.textSecondary),
                        const SizedBox(height: 12),
                        Text('点击选择 DOCX 文件',
                            style: TextStyle(
                                fontSize: MaoType.h3, color: ac.accent)),
                        const SizedBox(height: 4),
                        Text('AI 将自动识别题目、选项和答案',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                        const SizedBox(height: 4),
                        // v1.0.2 对齐里程碑：JSON 直导入库提示
                        Text('导入 .json 题库文件，无需 AI 解析，题目答案直接入库',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                            '选择本软件导出的 .json 题库文件（可多选）。导入完成后会显示导入报告。',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 已选文件（v1.27：随整页滚动，不再被压在 Expanded 小区域）
                if (_selectedFiles.isNotEmpty) ...[
                  Text('已选文件',
                      style: TextStyle(
                          fontSize: MaoType.body,
                          fontWeight: FontWeight.w600,
                          color: ac.textPrimary)),
                  const SizedBox(height: 8),
                  for (var index = 0; index < _selectedFiles.length; index++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.description_outlined,
                            color: ac.accent),
                        // v1.0.2 设计审查修复：取文件名用 path 包 basename
                        title: Text(p.basename(_selectedFiles[index]),
                            style: const TextStyle(fontSize: MaoType.body)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: isProcessing
                              ? null
                              : () => setState(
                                  () => _selectedFiles.removeAt(index)),
                        ),
                      ),
                    ),
                ],
              ],
            ),
            ),
          );
        },
      ),
      
      // v1.27 修复：余额/开始导入/进度固定在页底——文件再多也能滚动查看，
      // 操作按钮始终可见（小窗口不再被挤出屏幕）。
      bottomNavigationBar: Consumer<AppState>(
        builder: (context, appState, _) {
          final isProcessing = appState.importTaskActive;
          if (_selectedFiles.isEmpty && !isProcessing) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: ac.background,
                border: Border(
                    top: BorderSide(
                        color: ac.border.withOpacity(0.6))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 余额提示（选了文件且余额已加载时显示）
                  if (_selectedFiles.isNotEmpty &&
                      appState.aiService?.cachedBalance != null)
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
                                fontSize: MaoType.body, color: ac.textSecondary),
                          );
                        },
                      ),
                    ),

                  // 开始导入（仅选了文件时显示；导入中展示进度）
                  if (_selectedFiles.isNotEmpty)
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
                        style: const TextStyle(fontSize: MaoType.h3),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ac.accent,
                        foregroundColor: ac.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(MaoRadius.small)),
                      ),
                      onPressed: isProcessing
                          ? null
                          : () {
                              if (_selectedFiles.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('请先选择文件')),
                                );
                                return;
                              }
                              // v1.27 后台导入：JSON 直接入库 + DOCX 走 AI 解析，
                              // 全部在应用层执行；立即回首页（进度在首页展示、
                              // 完成弹提示），导入期间可随时离开本页。
                              final jsonFiles = _selectedFiles
                                  .where((f) =>
                                      f.toLowerCase().endsWith('.json'))
                                  .toList();
                              final docxFiles = _selectedFiles
                                  .where((f) =>
                                      f.toLowerCase().endsWith('.docx') ||
                                      f.toLowerCase().endsWith('.doc'))
                                  .toList();
                              unawaited(appState.startBackgroundImport(
                                jsonFiles: jsonFiles,
                                docxFiles: docxFiles,
                              ));
                              setState(() => _selectedFiles.clear());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '导入任务已开始，进度见首页，可先浏览其他页面')),
                              );
                              Navigator.pop(context);
                            },
                    ),
                  ),

                  // v1.27 进度展示：精确进度条 + 状态文字（任务在应用层继续，
                  // 离开本页后首页同步展示）
                  if (isProcessing)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(MaoRadius.chip),
                            child: LinearProgressIndicator(
                              value: appState.importProgress.clamp(0.0, 1.0),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(appState.importStatus,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: MaoType.body, color: ac.textSecondary)),
                          const SizedBox(height: 4),
                          Text('可离开本页，导入会继续在后台进行，进度在首页展示',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: MaoType.body,
                                  color: ac.textSecondary.withOpacity(0.8))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
