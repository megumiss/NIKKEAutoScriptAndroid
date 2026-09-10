import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/api/instance_info.dart';
import 'package:nkas_mobile_preview/core/api/queue_info.dart';
import 'package:nkas_mobile_preview/core/widgets/avatar.dart';
import 'package:nkas_mobile_preview/core/widgets/buttons.dart';
import 'package:nkas_mobile_preview/core/widgets/icon_box.dart';
import 'package:nkas_mobile_preview/core/widgets/log_line.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/select_box.dart';
import 'package:nkas_mobile_preview/core/widgets/status.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/core/widgets/tag.dart';
import 'package:nkas_mobile_preview/features/logs/logs_page.dart';
import 'package:nkas_mobile_preview/theme.dart';

enum InstanceTab { overview, tasks, schedule, liveLogs, screen }

class InstancesPage extends StatelessWidget {
  const InstancesPage({
    required this.selected,
    required this.selectedInstance,
    required this.instances,
    required this.loading,
    required this.toggleLoading,
    required this.error,
    required this.avatarUrl,
    required this.queue,
    required this.queueLoading,
    required this.queueError,
    required this.running,
    required this.tab,
    required this.onTabChanged,
    required this.onToggle,
    required this.onSelectInstance,
    super.key,
  });
  final String selected;
  final InstanceInfo? selectedInstance;
  final List<InstanceInfo> instances;
  final bool loading;
  final bool toggleLoading;
  final String? error;
  final String? Function(InstanceInfo item) avatarUrl;
  final QueueInfo? queue;
  final bool queueLoading;
  final String? queueError;
  final bool running;
  final InstanceTab tab;
  final ValueChanged<InstanceTab> onTabChanged;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelectInstance;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final inset = nkasPageInset(context);
    final displayName =
        selectedInstance?.name ??
        (loading
            ? '加载中…'
            : error == null
            ? '暂无实例'
            : '实例加载失败');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('切换实例并管理任务、调度和画面'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Surface(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Avatar(
                  text: selectedInstance?.name.characters.first ?? '实',
                  size: 38,
                  fontSize: 15,
                  background: scheme.accentSoft,
                  foreground: scheme.configIconText,
                  imageUrl: selectedInstance == null
                      ? null
                      : avatarUrl(selectedInstance!),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selectedInstance != null) ...[
                        const SizedBox(width: 7),
                        Status(status: selectedInstance!.status),
                      ],
                    ],
                  ),
                ),
                CompactButton(
                  icon: LucideIcons.layers3,
                  label: '切换',
                  onPressed: () => _showInstancePicker(context),
                ),
                if (selectedInstance != null) ...[
                  const SizedBox(width: 7),
                  PrimaryButton(
                    icon: toggleLoading
                        ? LucideIcons.loaderCircle
                        : running
                        ? LucideIcons.square
                        : LucideIcons.play,
                    label: toggleLoading
                        ? '处理中…'
                        : running
                        ? '停止'
                        : '启动',
                    onPressed: onToggle,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
        _InstanceTabs(tab: tab, onChanged: onTabChanged),
        Expanded(
          child: _InstanceBody(
            tab: tab,
            queue: queue,
            loading: queueLoading,
            error: queueError,
          ),
        ),
      ],
    );
  }

  void _showInstancePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('切换实例', style: ShadTheme.of(context).textTheme.h3),
              const SizedBox(height: 8),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (instances.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    error == null ? '暂无实例' : '实例加载失败，请检查后端连接',
                    style: ShadTheme.of(context).textTheme.muted,
                  ),
                ),
              for (final item in instances)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(
                    text: item.name.characters.first,
                    imageUrl: avatarUrl(item),
                  ),
                  title: Text(item.name),
                  trailing: Icon(
                    item.name == selected
                        ? LucideIcons.check
                        : LucideIcons.chevronRight,
                  ),
                  onTap: () {
                    onSelectInstance(item.name);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstanceTabs extends StatelessWidget {
  const _InstanceTabs({required this.tab, required this.onChanged});
  final InstanceTab tab;
  final ValueChanged<InstanceTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    const items = [
      (InstanceTab.overview, '概览'),
      (InstanceTab.tasks, '任务配置'),
      (InstanceTab.schedule, '调度设置'),
      (InstanceTab.liveLogs, '实时日志'),
      (InstanceTab.screen, '画面'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 17),
      child: SizedBox(
        height: 36,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: nkasPageInset(context)),
          child: Row(
            children: [
              for (final item in items)
                InkWell(
                  onTap: () => onChanged(item.$1),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              item.$2,
                              style: TextStyle(
                                color: tab == item.$1
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.mutedForeground,
                                fontSize: 12,
                                fontWeight: tab == item.$1
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          height: 2,
                          decoration: BoxDecoration(
                            color: tab == item.$1
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstanceBody extends StatelessWidget {
  const _InstanceBody({
    required this.tab,
    required this.queue,
    required this.loading,
    required this.error,
  });
  final InstanceTab tab;
  final QueueInfo? queue;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
      children: switch (tab) {
        InstanceTab.overview => [
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 36),
                child: CircularProgressIndicator(),
              ),
            )
          else if (queue == null)
            Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Text(error == null ? '暂无队列数据' : '队列加载失败'),
            )
          else ...[
            _QueueGroup.fromItems(
              label: '运行中',
              colorKind: 0,
              items: queue!.running,
            ),
            const SizedBox(height: 16),
            _QueueGroup.fromItems(
              label: '队列中',
              colorKind: 1,
              items: queue!.pending,
            ),
            const SizedBox(height: 16),
            _QueueGroup.fromItems(
              label: '等待中',
              colorKind: 2,
              items: queue!.waiting,
            ),
          ],
        ],
        InstanceTab.tasks => const [
          _ConfigGroup(
            title: '日常',
            rows: [
              ('前哨基地', '领取派遣、商店与基地奖励', true, LucideIcons.home),
              ('咨询', '自动完成妮姬咨询', true, LucideIcons.messageCircle),
            ],
          ),
          SizedBox(height: 16),
          _ConfigGroup(
            title: '活动',
            rows: [
              ('剧情活动', '推图、签到、商店与协同', true, LucideIcons.scrollText),
              ('协同作战', '大型活动内置协同任务', false, LucideIcons.swords),
            ],
          ),
          SizedBox(height: 16),
          _ConfigGroup(
            title: '工具',
            rows: [('设备与通知', '分辨率、通知和设备相关配置', true, LucideIcons.wrench)],
          ),
        ],
        InstanceTab.schedule => const [_SchedulePanel()],
        InstanceTab.liveLogs => const [_LiveLogPanel()],
        InstanceTab.screen => const [_ScreenPanel()],
      },
    );
  }
}

class _QueueGroup extends StatelessWidget {
  factory _QueueGroup.fromItems({
    required String label,
    required int colorKind,
    required List<QueueItem> items,
  }) => _QueueGroup(
    label: label,
    colorKind: colorKind,
    rows: [for (final item in items) (item.name, item.command, item.nextRun)],
  );

  const _QueueGroup({
    required this.label,
    required this.colorKind,
    required this.rows,
  });
  final String label;
  final int colorKind;
  final List<(String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = colorKind == 0
        ? theme.colorScheme.success
        : colorKind == 1
        ? theme.colorScheme.primary
        : theme.colorScheme.mutedForeground;
    // 原型任务行图标：运行中 loader-circle、队列中 list-ordered、等待中 clock-3
    final icon = colorKind == 0
        ? LucideIcons.loaderCircle
        : colorKind == 1
        ? LucideIcons.listOrdered
        : LucideIcons.clock3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 8),
          child: Row(
            children: [
              Dot(color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _QueueRow(
                  name: rows[i].$1,
                  detail: rows[i].$2,
                  time: rows[i].$3,
                  color: color,
                  icon: icon,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.name,
    required this.detail,
    required this.time,
    required this.color,
    required this.icon,
  });
  final String name;
  final String detail;
  final String time;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          IconBox(icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(detail, style: theme.textTheme.muted),
              ],
            ),
          ),
          Tag(label: time, color: color),
          const SizedBox(width: 5),
          Icon(
            LucideIcons.chevronRight,
            size: 15,
            color: theme.colorScheme.mutedForeground,
          ),
        ],
      ),
    );
  }
}

class _ConfigGroup extends StatelessWidget {
  const _ConfigGroup({required this.title, required this.rows});
  final String title;
  final List<(String, String, bool, IconData)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 8),
          child: Text(title, style: theme.textTheme.muted),
        ),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IconBox(
                        icon: rows[i].$4,
                        color: scheme.configIconText,
                        background: scheme.configIconBg,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].$1,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(rows[i].$2, style: theme.textTheme.muted),
                          ],
                        ),
                      ),
                      Tag(
                        label: rows[i].$3 ? '已启用' : '未启用',
                        color: rows[i].$3
                            ? scheme.success
                            : scheme.mutedForeground,
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: scheme.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SchedulePanel extends StatefulWidget {
  const _SchedulePanel();

  @override
  State<_SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<_SchedulePanel> {
  bool daily = true;
  bool event = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ScheduleRow(
          title: '每日任务',
          subtitle: '下次运行：明日 05:00',
          time: '05:00',
          enabled: daily,
          onChanged: (value) => setState(() => daily = value),
        ),
        const SizedBox(height: 10),
        _ScheduleRow(
          title: '剧情活动',
          subtitle: '下次运行：明日 06:00',
          time: '06:00',
          enabled: event,
          onChanged: (value) => setState(() => event = value),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          icon: LucideIcons.save,
          label: '保存调度设置',
          onPressed: () {},
        ),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.enabled,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final String time;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Surface(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: theme.textTheme.muted),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: SelectBox(label: '每天')),
              const SizedBox(width: 7),
              Expanded(child: SelectBox(label: time)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveLogPanel extends StatelessWidget {
  const _LiveLogPanel();

  @override
  Widget build(BuildContext context) {
    return LogCard(
      title: '实时日志',
      rows: const [
        ('09:32:04', 'INFO', null, '每日任务：开始执行前哨基地', LogKind.info),
        ('09:32:01', 'INFO', null, '设备连接已确认，进入任务队列', LogKind.info),
        ('09:31:58', 'DEBUG', null, '检测当前页面：前哨基地', LogKind.info),
        ('09:31:44', 'WARN', null, '等待游戏窗口响应，重试 1/3', LogKind.warn),
      ],
    );
  }
}

class _ScreenPanel extends StatelessWidget {
  const _ScreenPanel();

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: EdgeInsets.zero,
      color: NkasColors.screenBg,
      child: const AspectRatio(
        aspectRatio: 9 / 16,
        child: Center(
          child: Text('暂无画面', style: TextStyle(color: NkasColors.screenText)),
        ),
      ),
    );
  }
}
