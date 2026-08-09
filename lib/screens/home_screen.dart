import 'practice_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../widgets/ai_response_widget.dart';
import 'bank_manage_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'quiz_screen.dart';
import 'error_book_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      appState.refreshWeaknessAnalysis();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('呆猫刷题宝',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await appState.init();
              await appState.refreshWeaknessAnalysis();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API 余额不足警告
                  if (appState.aiService != null &&
                      appState.aiService!.cachedBalance != null &&
                      appState.aiService!.cachedBalance! > 0 &&
                      appState.aiService!.cachedBalance! < 1.0)
                    _buildBalanceWarning(cs),
                  _buildStatsCards(appState, cs),
                  const SizedBox(height: 24),
                  _buildWeaknessSection(appState, cs),
                  const SizedBox(height: 24),
                  _buildQuickActions(appState, cs),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      '本软件由b站：笨蛋鱼坏蛋猫 开发 | v1.26.6.17',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withOpacity(0.4)),
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

  Widget _buildBalanceWarning(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFC107)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFF856404)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'API 余额不足 ¥1，建议尽快充值以免影响使用',
              style: TextStyle(fontSize: 13, color: Colors.brown[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(AppState appState, ColorScheme cs) {
    final stats = appState.homeStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.timer_outlined,
                label: '累计刷题时长',
                value: stats?.formattedDuration ?? '0分钟',
                color: cs.primary,
                cs: cs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.quiz_outlined,
                label: '总刷题量',
                value: '${stats?.totalQuestions ?? 0} 题',
                color: const Color(0xFF5CB85C),
                cs: cs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up,
                label: '平均正确率',
                value: stats?.formattedAccuracy ?? '0%',
                color: cs.secondary,
                cs: cs,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '仅统计按「结束」完成的会话时长，中途退出不计',
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildWeaknessSection(AppState appState, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: cs.secondary),
              const SizedBox(width: 8),
              Text('薄弱点分析',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新', style: TextStyle(fontSize: 12)),
                onPressed: () => appState.refreshWeaknessAnalysis(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (appState.weaknessAnalysis == null)
            Center(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: CircularProgressIndicator(color: cs.primary),
            ))
          else
            AiResponseWidget(
              text: appState.weaknessAnalysis!,
              fontSize: 14,
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(AppState appState, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('快速操作',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.rocket_launch_rounded,
                customImage: 'assets/burst_icon.png',
                label: '定向爆破',
                subtitle: appState.selectedBankIds.isEmpty
                    ? '请先选择题库'
                    : '已选${appState.selectedBankIds.length}个题库，${appState.selectedQuestionCount >= 9999 ? '全部' : '${appState.selectedQuestionCount >= 9999 ? '全部' : '${appState.selectedQuestionCount}题'}'}',
                color: cs.primary,
                cs: cs,
                onTap: appState.selectedBankIds.isEmpty
                    ? null
                    : () => _showCountPicker(context, appState),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.library_add_outlined,
                label: '管理题库',
                subtitle: '${appState.banks.length} 个题库',
                color: const Color(0xFF5CB85C),
                cs: cs,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const BankManageScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.replay_rounded,
          label: '错题本',
          subtitle: '使用FSRS算法全权生成',
          color: cs.error,
          cs: cs,
          fullWidth: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ErrorBookScreen()),
          ),
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.upload_file,
          label: '导入题库',
          subtitle: '支持 DOC/DOCX 格式批量上传',
          color: cs.secondary,
          cs: cs,
          fullWidth: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ImportScreen()),
          ),
        ),
      ],
    );
  }

  void _showCountPicker(BuildContext context, AppState appState) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('选择刷题数量', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              ...[10, 20, 30, 50, 80, 100].map((n) => ChoiceChip(
                label: Text('$n 题'), selected: appState.selectedQuestionCount == n,
                onSelected: (_) { appState.setQuestionCount(n); Navigator.pop(ctx); _showQuizModePicker(context, appState); },
              )),
              ChoiceChip(label: const Text('全部'), selected: false, onSelected: (_) { appState.setQuestionCount(9999); Navigator.pop(ctx); _showQuizModePicker(context, appState); }),
              ChoiceChip(label: const Text('自定义'), selected: false, onSelected: (_) { Navigator.pop(ctx); _showCustomCountDialog(context, appState); }),
            ]),
            const SizedBox(height: 12),
            Text('当前: ${appState.selectedQuestionCount >= 9999 ? '全部' : '${appState.selectedQuestionCount} 题'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  void _showCustomCountDialog(BuildContext context, AppState appState) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义题目数'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '输入题数', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            final n = int.tryParse(ctrl.text);
            if (n != null && n > 0) { appState.setQuestionCount(n); Navigator.pop(ctx); _showQuizModePicker(context, appState); }
          }, child: const Text('确定')),
        ],
      ),
    );
  }

  void _showQuizModePicker(BuildContext context, AppState appState) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('选择刷题模式',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('已选 ${appState.selectedBankIds.length} 个题库，${appState.selectedQuestionCount >= 9999 ? '全部' : '${appState.selectedQuestionCount} 题'}/轮',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              _ModeOption(
                icon: Icons.flash_on_rounded,
                label: '正常刷题',
                desc: '答完即判，立刻校对解析',
                color: cs.primary,
                cs: cs,
                onTap: () {
                  Navigator.pop(ctx);
                  _startQuiz(context, appState);
                },
              ),
              const SizedBox(height: 10),
              _ModeOption(
                icon: Icons.edit_square,
                label: '练习',
                desc: '答题卡模式，限时/不限时，统一批改',
                color: cs.secondary,
                cs: cs,
                onTap: () {
                  Navigator.pop(ctx);
                  _startPractice(context, appState);
                },
              ),
              const SizedBox(height: 10),
              _ModeOption(
                icon: Icons.visibility_rounded,
                label: '背题模式',
                desc: '直接展示答案，快速浏览记忆',
                color: cs.tertiary,
                cs: cs,
                onTap: () {
                  Navigator.pop(ctx);
                  _startMemorize(context, appState);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startQuiz(BuildContext context, AppState appState) async {
    if (!appState.settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先在设置中配置 DeepSeek API Key'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    await appState.startQuiz();

    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuizScreen()),
    );
  }

  Future<void> _startPractice(BuildContext context, AppState appState) async {
    if (!appState.settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 API Key'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (appState.selectedBankIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在首页选择题库')),
      );
      return;
    }
    await appState.startQuiz();
    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PracticeEntryScreen(questions: appState.quizQuestions),
    ));
  }

  Future<void> _startMemorize(BuildContext context, AppState appState) async {
    if (!appState.settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 API Key'), backgroundColor: Colors.orange),
      );
      return;
    }
    appState.noShuffle = true;
    await appState.startQuiz();
    appState.noShuffle = false;
    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuizScreen(quizMode: QuizMode.memorize),
    ));
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ColorScheme cs;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Text(value,
                key: ValueKey(value),
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String? customImage;
  final String label;
  final String subtitle;
  final Color color;
  final ColorScheme cs;
  final VoidCallback? onTap;
  final bool fullWidth;

  const _ActionCard({
    required this.icon,
    this.customImage,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.cs,
    this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration:
                  BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: customImage != null
                  ? Image.asset(customImage!, width: 36, height: 36, color: color)
                  : Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final ColorScheme cs;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.cs,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: enabled ? cs.surfaceContainerHighest : cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? cs.outlineVariant : cs.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(enabled ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: enabled ? color : cs.onSurfaceVariant, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: enabled ? cs.onSurface : cs.onSurfaceVariant)),
                      if (!enabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.outlineVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('即将开放',
                              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 12,
                          color: enabled ? cs.onSurfaceVariant : cs.onSurfaceVariant.withOpacity(0.5))),
                ],
              ),
            ),
            if (enabled)
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}
