import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/api/instance_info.dart';
import 'package:nkas_mobile_preview/core/api/queue_info.dart';
import 'package:nkas_mobile_preview/core/api/screenshot_frame.dart';
import 'package:nkas_mobile_preview/core/api/schedule_info.dart';
import 'package:nkas_mobile_preview/core/widgets/avatar.dart';
import 'package:nkas_mobile_preview/core/widgets/buttons.dart';
import 'package:nkas_mobile_preview/core/widgets/icon_box.dart';
import 'package:nkas_mobile_preview/core/widgets/log_line.dart';
import 'package:nkas_mobile_preview/core/widgets/field_select.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
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
    required this.loadScreenshot,
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
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
  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;
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
            selected: selected,
            loadScreenshot: loadScreenshot,
            loadSchedule: loadSchedule,
            saveSchedule: saveSchedule,
            resetSchedule: resetSchedule,
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
    required this.selected,
    required this.loadScreenshot,
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
  });
  final InstanceTab tab;
  final QueueInfo? queue;
  final bool loading;
  final String? error;
  final String selected;
  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;

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
        InstanceTab.schedule => [
          _SchedulePanel(
            key: ValueKey(selected),
            loadSchedule: loadSchedule,
            saveSchedule: saveSchedule,
            resetSchedule: resetSchedule,
          ),
        ],
        InstanceTab.liveLogs => const [_LiveLogPanel()],
        InstanceTab.screen => [
          _ScreenPanel(key: ValueKey(selected), loadScreenshot: loadScreenshot),
        ],
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
  const _SchedulePanel({
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
    super.key,
  });

  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;

  @override
  State<_SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<_SchedulePanel> {
  List<ScheduleTask> tasks = const [];
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.loadSchedule();
      if (mounted) setState(() => tasks = value);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save(List<Map<String, dynamic>> changes) async {
    setState(() => saving = true);
    try {
      await widget.saveSchedule(changes);
      await _load();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reset() async {
    setState(() => saving = true);
    try {
      await widget.resetSchedule();
      await _load();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: CircularProgressIndicator(),
          )
        else if (tasks.isEmpty)
          Text(error == null ? '暂无调度任务' : '调度加载失败')
        else ...[
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ScheduleRow(
              task: tasks[i],
              disabled: saving,
              onChanged: (change) {
                final next = tasks[i];
                setState(() {
                  tasks = [
                    ...tasks.sublist(0, i),
                    ScheduleTask(
                      command: next.command,
                      name: next.name,
                      enabled: change['enable'] as bool? ?? next.enabled,
                      locked: next.locked,
                      enableLocked: next.enableLocked,
                      cadence: change['cadence']?.toString() ?? next.cadence,
                      cadenceLocked: next.cadenceLocked,
                      nextRun: next.nextRun,
                      dailyTimes:
                          change['daily_times']?.toString() ?? next.dailyTimes,
                      weeklyDays: next.weeklyDays,
                      weeklyTime:
                          change['weekly_time']?.toString() ?? next.weeklyTime,
                      monthlyDay: next.monthlyDay,
                      monthlyTime:
                          change['monthly_time']?.toString() ??
                          next.monthlyTime,
                    ),
                    ...tasks.sublist(i + 1),
                  ];
                });
              },
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  icon: LucideIcons.rotateCcw,
                  label: '还原默认',
                  onPressed: saving ? null : _reset,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  icon: LucideIcons.save,
                  label: saving ? '保存中…' : '保存调度设置',
                  onPressed: saving
                      ? null
                      : () => _save([
                          for (final task in tasks)
                            {
                              'command': task.command,
                              'enable': task.enabled,
                              'cadence': task.cadence,
                              'daily_times': task.dailyTimes,
                              'weekly_days': task.weeklyDays,
                              'weekly_time': task.weeklyTime,
                              'monthly_day': task.monthlyDay,
                              'monthly_time': task.monthlyTime,
                            },
                        ]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.task,
    required this.disabled,
    required this.onChanged,
  });
  final ScheduleTask task;
  final bool disabled;
  final ValueChanged<Map<String, dynamic>> onChanged;

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
                      task.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.nextRun.isEmpty ? '未安排下次运行' : '下次运行：${task.nextRun}',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
              ),
              Switch(
                value: task.enabled,
                onChanged: disabled || task.enableLocked
                    ? null
                    : (value) => onChanged({'enable': value}),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FieldSelect(
                  label: '周期',
                  value: _cadenceLabel(task.cadence),
                  options: const [
                    FieldSelectOption('daily', '每天'),
                    FieldSelectOption('weekly', '每周'),
                    FieldSelectOption('monthly', '每月'),
                  ],
                  onChanged: disabled || task.cadenceLocked
                      ? null
                      : (value) => onChanged({'cadence': value}),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: TextFormField(
                  key: ValueKey('${task.command}-${task.cadence}'),
                  initialValue: task.activeTime,
                  enabled: !disabled && !task.locked,
                  decoration: const InputDecoration(labelText: '时间'),
                  onChanged: (value) {
                    final key = switch (task.cadence) {
                      'weekly' => 'weekly_time',
                      'monthly' => 'monthly_time',
                      _ => 'daily_times',
                    };
                    onChanged({key: value});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _cadenceLabel(String value) => switch (value) {
    'weekly' => '每周',
    'monthly' => '每月',
    _ => '每天',
  };
}

class _LiveLogPanel extends StatelessWidget {
  const _LiveLogPanel();

  @override
  Widget build(BuildContext context) {
    return LogCard(
      title: '实时日志',
      rows: const [
        LogRowData(
          time: '09:32:04',
          level: 'INFO',
          source: null,
          message: '每日任务：开始执行前哨基地',
          kind: LogKind.info,
        ),
        LogRowData(
          time: '09:32:01',
          level: 'INFO',
          source: null,
          message: '设备连接已确认，进入任务队列',
          kind: LogKind.info,
        ),
        LogRowData(
          time: '09:31:58',
          level: 'DEBUG',
          source: null,
          message: '检测当前页面：前哨基地',
          kind: LogKind.info,
        ),
        LogRowData(
          time: '09:31:44',
          level: 'WARN',
          source: null,
          message: '等待游戏窗口响应，重试 1/3',
          kind: LogKind.warn,
        ),
      ],
    );
  }
}

class _ScreenPanel extends StatefulWidget {
  const _ScreenPanel({required this.loadScreenshot, super.key});

  final Future<ScreenshotFrame?> Function() loadScreenshot;

  @override
  State<_ScreenPanel> createState() => _ScreenPanelState();
}

class _ScreenPanelState extends State<_ScreenPanel> {
  ScreenshotFrame? frame;
  bool loading = false;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final value = await widget.loadScreenshot();
      if (!mounted) return;
      setState(() {
        frame = value;
        error = null;
      });
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Surface(
      padding: EdgeInsets.zero,
      color: NkasColors.screenBg,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: frame == null
                ? Center(
                    child: Text(
                      error == null ? (loading ? '正在获取画面…' : '暂无画面') : '画面加载失败',
                      style: const TextStyle(color: NkasColors.screenText),
                    ),
                  )
                : Image.memory(
                    frame!.bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: theme.colorScheme.card,
            child: Row(
              children: [
                Text(
                  frame == null ? '未连接' : _captureLabel(frame!.capturedAt),
                  style: theme.textTheme.muted,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: loading ? null : _load,
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  label: const Text('刷新画面'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _captureLabel(double? timestamp) {
    if (timestamp == null) return '实时 · 2s';
    final date = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).round(),
    ).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '捕获于 ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }
}
