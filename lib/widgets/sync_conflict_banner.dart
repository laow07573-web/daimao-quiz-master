import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync/sync_engine.dart';
import '../services/sync/sync_models.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import 'kit/mj_kit.dart';

/// 同名题库冲突提示（挂首页）。
///
/// 2026-10-09 用户要求：「同名题库的话，先进行校验比较两份题库和题库附属的内容
/// 的文件是否不一样，若一样则不更新，若不一样则提示是否覆盖或者增添。」
/// 并指定提示挂载位置：「关于同名题库的导入的提示挂在首页就好了」。
///
/// 同步可能在后台发生（那时弹不出对话框），所以冲突由 [SyncEngine] 挂起，
/// 回到首页就能看到，由用户决定**覆盖**（用对端整套替换）还是**增添**
/// （只把对端多出来的题并进来）。没有冲突时整块不占位。
class SyncConflictBanner extends StatelessWidget {
  const SyncConflictBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    // 用可空读取：首页也可能在没有同步能力的环境里渲染（只挂 AppState 的
    // widget 测试、桌面端未启动同步引擎等）。此时整块不占位即可，
    // 不该抛 ProviderNotFoundException 把整个首页打挂。
    final sync = context.watch<SyncEngine?>();
    if (sync == null) return const SizedBox.shrink();
    final conflicts = sync.pendingConflicts;
    if (conflicts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: MaoSpace.sm),
      child: MJSurface(
        tone: MJTone.alt,
        onTap: () => _showConflictSheet(context, sync, conflicts),
        padding: const EdgeInsets.symmetric(
            horizontal: MaoSpace.sm, vertical: MaoSpace.sm),
        child: Row(
          children: [
            Icon(Icons.sync_problem_outlined, size: 18, color: ac.accent),
            const SizedBox(width: MaoSpace.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '有 ${conflicts.length} 个同名题库待处理',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        fontWeight: FontWeight.w600,
                        color: ac.textPrimary),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '同步时发现同名题库内容不一样，需要你决定是覆盖还是增添',
                    style: TextStyle(
                        fontSize: MaoType.caption, color: ac.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: ac.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showConflictSheet(
      BuildContext context, SyncEngine sync, List<SyncBankConflict> conflicts) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // 与全站弹层一致：自带标题栏，不要框架拖拽手柄（否则下方露透明带）
      showDragHandle: false,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          final ac = AppThemeColors.of(context);
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(MaoSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('同名题库',
                    style: TextStyle(
                        fontSize: MaoType.h2,
                        fontWeight: FontWeight.bold,
                        color: ac.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  '这些题库在两端同名但内容不一样。覆盖＝用对端整套替换本机；'
                  '增添＝只把对端多出来的题并进本机，本机已有的题不动。',
                  style: TextStyle(
                      fontSize: MaoType.caption,
                      color: ac.textSecondary,
                      height: 1.4),
                ),
                const SizedBox(height: MaoSpace.sm),
                for (final c in conflicts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MaoSpace.sm),
                    child: _ConflictCard(
                      conflict: c,
                      onOverwrite: () => _decide(sheetContext, sync, c, true),
                      onAppend: () => _decide(sheetContext, sync, c, false),
                      onDismiss: () {
                        sync.dismissConflict(c);
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _decide(BuildContext context, SyncEngine sync,
      SyncBankConflict conflict, bool overwrite) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final affected = await sync.resolveConflict(conflict, overwrite: overwrite);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(overwrite
          ? '已用对端内容覆盖「${conflict.name}」'
          : '已把对端多出的 $affected 题增添到「${conflict.name}」'),
    ));
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.onOverwrite,
    required this.onAppend,
    required this.onDismiss,
  });

  final SyncBankConflict conflict;
  final VoidCallback onOverwrite;
  final VoidCallback onAppend;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(MaoSpace.sm),
      decoration: BoxDecoration(
        color: ac.surfaceAlt,
        borderRadius: MaoRadius.controlBorder,
        border: Border.all(color: ac.border, width: MaoLine.width),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(conflict.name,
              style: TextStyle(
                  fontSize: MaoType.body,
                  fontWeight: FontWeight.w600,
                  color: ac.textPrimary)),
          const SizedBox(height: 2),
          Text(
            '${conflict.summary}'
            '${conflict.peerDeviceName.isEmpty ? '' : ' · 来自 ${conflict.peerDeviceName}'}',
            style:
                TextStyle(fontSize: MaoType.caption, color: ac.textSecondary),
          ),
          const SizedBox(height: MaoSpace.xs),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: conflict.additionCount > 0 ? onAppend : null,
                child: Text(conflict.additionCount > 0
                    ? '增添（+${conflict.additionCount} 题）'
                    : '增添'),
              ),
              const SizedBox(width: MaoSpace.xs),
              OutlinedButton(
                onPressed: onOverwrite,
                child: const Text('覆盖'),
              ),
              const Spacer(),
              TextButton(onPressed: onDismiss, child: const Text('暂不处理')),
            ],
          ),
        ],
      ),
    );
  }
}
