"""批量把页面的 Material ColorScheme 用法迁移到 Mao Des 语义色。

用法：python migrate_colors.py <文件路径...>
规则：
  cs.onSurfaceVariant      -> ac.textSecondary
  cs.onSurface             -> ac.textPrimary
  cs.surfaceContainerHighest -> ac.surfaceAlt
  cs.surfaceContainer*     -> ac.surfaceAlt
  cs.primary               -> ac.accent
  cs.onPrimary             -> ac.onAccent
  cs.primaryContainer      -> ac.accentSoft
  cs.onPrimaryContainer    -> ac.accent
  cs.secondary / tertiary  -> ac.textSecondary / ac.accent
  cs.error                 -> ac.danger
  cs.onError               -> ac.onAccent
  cs.errorContainer        -> ac.dangerSoft
  cs.outlineVariant        -> ac.border
  cs.outline               -> ac.border
  cs.surface               -> ac.background
同时把局部变量 `final cs = Theme.of(context).colorScheme;` 换成 `final ac = AppThemeColors.of(context);`
"""
import re
import sys

MAP = [
    ('cs.onSurfaceVariant', 'ac.textSecondary'),
    ('cs.surfaceContainerHighest', 'ac.surfaceAlt'),
    ('cs.surfaceContainerHigh', 'ac.surfaceAlt'),
    ('cs.surfaceContainerLowest', 'ac.surface'),
    ('cs.surfaceContainerLow', 'ac.surface'),
    ('cs.surfaceContainer', 'ac.surfaceAlt'),
    ('cs.onSurface', 'ac.textPrimary'),
    ('cs.primaryContainer', 'ac.accentSoft'),
    ('cs.onPrimaryContainer', 'ac.accent'),
    ('cs.onPrimary', 'ac.onAccent'),
    ('cs.primary', 'ac.accent'),
    ('cs.tertiaryContainer', 'ac.accentSoft'),
    ('cs.onTertiaryContainer', 'ac.textPrimary'),
    ('cs.tertiary', 'ac.accent'),
    ('cs.secondaryContainer', 'ac.surfaceAlt'),
    ('cs.onSecondaryContainer', 'ac.textPrimary'),
    ('cs.secondary', 'ac.textSecondary'),
    ('cs.errorContainer', 'ac.dangerSoft'),
    ('cs.onErrorContainer', 'ac.danger'),
    ('cs.onError', 'ac.onAccent'),
    ('cs.error', 'ac.danger'),
    ('cs.outlineVariant', 'ac.border'),
    ('cs.outline', 'ac.border'),
    ('cs.surface', 'ac.background'),
    ('cs.shadow', 'ac.border'),
]


def migrate(path):
    with open(path, encoding='utf-8') as f:
        s = f.read()

    # 1) 局部变量声明替换
    s = s.replace('final cs = Theme.of(context).colorScheme;',
                  'final ac = AppThemeColors.of(context);')

    # 2) 颜色名映射
    for a, b in MAP:
        s = s.replace(a, b)

    # 3) 清理由映射产生的级联错误
    s = s.replace('ac.backgroundAlt', 'ac.surfaceAlt')
    s = s.replace('ac.backgroundContainer', 'ac.surfaceAlt')

    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)
    print('migrated:', path)


if __name__ == '__main__':
    for p in sys.argv[1:]:
        migrate(p)
