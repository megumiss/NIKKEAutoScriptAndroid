import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/widgets/icon_box.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.themeMode,
    required this.notifications,
    required this.autoScroll,
    required this.onThemeModeChanged,
    required this.onNotificationsChanged,
    required this.onAutoScrollChanged,
    super.key,
  });
  final ThemeMode themeMode;
  final bool notifications;
  final bool autoScroll;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<bool> onAutoScrollChanged;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    final warning = ShadTheme.of(context).colorScheme.warning;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 88),
      children: [
        const PageSubtitle('连接、验证与外观设置'),
        _SettingGroup(
          label: '验证与初始化',
          rows: [
            const _SettingRow(
              icon: LucideIcons.shieldCheck,
              title: 'STAR 验证',
              subtitle: '设备身份与授权状态 · 待验证',
            ),
            _SettingRow(
              icon: LucideIcons.sparkles,
              iconColor: warning,
              title: '初始化 NKAS',
              subtitle: '完成后才可以部署实例',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingGroup(
          label: '后端连接',
          rows: [
            _SettingRow(
              icon: LucideIcons.server,
              title: '后端地址',
              subtitle: 'http://127.0.0.1:12271',
              trailing: LucideIcons.pencil,
            ),
            _SettingRow(
              icon: LucideIcons.globe2,
              title: '原始 WebUI',
              subtitle: '打开完整控制台，使用更多高级功能',
              trailing: LucideIcons.externalLink,
            ),
            _SettingRow(
              icon: LucideIcons.squareArrowUp,
              title: '更新',
              subtitle: '检查源码的新版本',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingGroup(
          label: '外观与通知',
          rows: [
            _SettingRow(
              title: '主题',
              subtitle: '当前：${themeMode == ThemeMode.dark ? '深色' : '浅色'}',
              customTrailing: _ThemeSegment(
                themeMode: themeMode,
                onChanged: onThemeModeChanged,
              ),
            ),
            _SettingRow(
              title: '后台通知',
              subtitle: '任务完成或发生错误时提醒',
              customTrailing: Switch(
                value: notifications,
                onChanged: onNotificationsChanged,
              ),
            ),
            _SettingRow(
              title: '日志自动滚动',
              subtitle: '新日志到达时滚动到底部',
              customTrailing: Switch(
                value: autoScroll,
                onChanged: onAutoScrollChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingGroup(
          label: '关于',
          rows: [
            _SettingRow(
              title: 'NKAS Mobile Preview',
              subtitle: 'Flutter + shadcn_ui · 0.1.0-preview',
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.label, required this.rows});
  final String label;
  final List<_SettingRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 8),
          child: Text(label, style: theme.textTheme.muted),
        ),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.customTrailing,
  });
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final IconData? trailing;
  final Widget? customTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            if (icon != null) ...[
              IconBox(
                icon: icon!,
                color: iconColor ?? theme.colorScheme.success,
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            customTrailing ??
                Icon(
                  trailing ?? LucideIcons.chevronRight,
                  size: 15,
                  color: theme.colorScheme.mutedForeground,
                ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({required this.themeMode, required this.onChanged});
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _ThemeChoice(
            label: '浅色',
            selected: themeMode != ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.light),
          ),
          _ThemeChoice(
            label: '深色',
            selected: themeMode == ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.dark),
          ),
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.card : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.mutedForeground,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
