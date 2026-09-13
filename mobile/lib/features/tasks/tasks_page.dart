import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/instance_picker.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/queue_row.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/features/instances/live_log_panel.dart';
import 'package:nkas_mobile/features/instances/schedule_panel.dart';
import 'package:nkas_mobile/features/instances/schema_panel.dart';
import 'package:nkas_mobile/theme.dart';

/// 任务页顶部横向 tab：任务配置 + 队列三段（运行中/队列中/等待中）+ 实时日志 + 调度设置
enum TaskTab { config, running, pending, waiting, liveLog, schedule }

class TasksPage extends StatefulWidget {
  const TasksPage({
    required this.instances,
    required this.selected,
    required this.selectedInstance,
    required this.avatarUrl,
    required this.instancesLoading,
    required this.instancesError,
    required this.onSelectInstance,
    required this.queue,
    required this.queueLoading,
    required this.queueError,
    required this.schema,
    required this.schemaLoading,
    required this.schemaError,
    required this.loadSchema,
    required this.onPatch,
    required this.initialTaskKey,
    required this.onTaskKeyChanged,
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
    required this.liveLogUri,
    required this.running,
    required this.accessGranted,
    super.key,
  });

  final List<InstanceInfo> instances;
  final String selected;
  final InstanceInfo? selectedInstance;
  final String? Function(InstanceInfo item) avatarUrl;
  final bool instancesLoading;
  final String? instancesError;
  final ValueChanged<String> onSelectInstance;
  final QueueInfo? queue;
  final bool queueLoading;
  final String? queueError;
  final SchemaInfo? schema;
  final bool schemaLoading;
  final String? schemaError;
  final Future<void> Function() loadSchema;
  final Future<void> Function(String, Object?) onPatch;
  final String? initialTaskKey;
  final ValueChanged<String?> onTaskKeyChanged;
  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;
  final Uri liveLogUri;
  final bool running;
  final bool accessGranted;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  TaskTab tab = TaskTab.config;

  @override
  void didUpdateWidget(covariant TasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从实例详情点队列行进入：切到任务配置并展开对应任务
    if (widget.initialTaskKey != null &&
        widget.initialTaskKey != oldWidget.initialTaskKey) {
      tab = TaskTab.config;
    }
  }

  void _openTask(String key) {
    setState(() => tab = TaskTab.config);
    widget.onTaskKeyChanged(key);
  }

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('任务配置、队列、实时日志与调度'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: _InstanceBar(
            instances: widget.instances,
            selected: widget.selected,
            selectedInstance: widget.selectedInstance,
            avatarUrl: widget.avatarUrl,
            loading: widget.instancesLoading,
            error: widget.instancesError,
            onSelectInstance: widget.onSelectInstance,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 10, inset, 0),
          child: _TaskTabStrip(
            selected: tab,
            queue: widget.queue,
            onSelect: (value) => setState(() => tab = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _tabContent(inset)),
      ],
    );
  }

  Widget _tabContent(double inset) {
    switch (tab) {
      case TaskTab.config:
        return ListView(
          key: const ValueKey(TaskTab.config),
          padding: EdgeInsets.fromLTRB(inset, 0, inset, 88),
          children: [
            SchemaPanel(
              schema: widget.schema,
              loading: widget.schemaLoading,
              error: widget.schemaError,
              onReload: widget.loadSchema,
              onPatch: widget.onPatch,
              initialTaskKey: widget.initialTaskKey,
              onTaskKeyChanged: widget.onTaskKeyChanged,
            ),
          ],
        );
      case TaskTab.liveLog:
        return Padding(
          key: const ValueKey(TaskTab.liveLog),
          padding: EdgeInsets.fromLTRB(inset, 0, inset, 88),
          child: SizedBox.expand(
            child: LiveLogPanel(
              key: ValueKey(widget.selected),
              running: widget.running,
              uri: widget.liveLogUri,
              accessGranted: widget.accessGranted,
            ),
          ),
        );
      case TaskTab.schedule:
        return ListView(
          key: const ValueKey(TaskTab.schedule),
          padding: EdgeInsets.fromLTRB(inset, 0, inset, 88),
          children: [
            SchedulePanel(
              key: ValueKey(widget.selected),
              loadSchedule: widget.loadSchedule,
              saveSchedule: widget.saveSchedule,
              resetSchedule: widget.resetSchedule,
            ),
          ],
        );
      case TaskTab.running:
        return _queueList(
          inset,
          tab,
          widget.queue?.running,
          ShadTheme.of(context).colorScheme.success,
          LucideIcons.loaderCircle,
        );
      case TaskTab.pending:
        return _queueList(
          inset,
          tab,
          widget.queue?.pending,
          ShadTheme.of(context).colorScheme.primary,
          LucideIcons.listOrdered,
        );
      case TaskTab.waiting:
        return _queueList(
          inset,
          tab,
          widget.queue?.waiting,
          ShadTheme.of(context).colorScheme.mutedForeground,
          LucideIcons.clock3,
        );
    }
  }

  Widget _queueList(
    double inset,
    TaskTab key,
    List<QueueItem>? items,
    Color color,
    IconData icon,
  ) {
    if (widget.queueLoading && widget.queue == null) {
      return const Center(
        key: ValueKey('queue-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (widget.queue == null || items == null) {
      return Padding(
        key: ValueKey(key),
        padding: EdgeInsets.fromLTRB(inset, 28, inset, 0),
        child: Text(widget.queueError == null ? '暂无队列数据' : '队列加载失败'),
      );
    }
    if (items.isEmpty) {
      return Padding(
        key: ValueKey(key),
        padding: EdgeInsets.fromLTRB(inset, 28, inset, 0),
        child: Text('暂无任务', style: ShadTheme.of(context).textTheme.muted),
      );
    }
    return ListView(
      key: ValueKey(key),
      padding: EdgeInsets.fromLTRB(inset, 0, inset, 88),
      children: [
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                QueueRow(
                  name: items[i].name,
                  detail: items[i].command,
                  time: items[i].nextRun,
                  color: color,
                  icon: icon,
                  // schema 以后端 command 为键，而非本地化名称
                  onTap: () => _openTask(
                    items[i].command.isEmpty
                        ? items[i].name
                        : items[i].command,
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

/// 实例栏：头像 + 名称 + 状态 + 切换（与画面页头部同规格）
class _InstanceBar extends StatelessWidget {
  const _InstanceBar({
    required this.instances,
    required this.selected,
    required this.selectedInstance,
    required this.avatarUrl,
    required this.loading,
    required this.error,
    required this.onSelectInstance,
  });
  final List<InstanceInfo> instances;
  final String selected;
  final InstanceInfo? selectedInstance;
  final String? Function(InstanceInfo item) avatarUrl;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSelectInstance;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final displayName =
        selectedInstance?.name ??
        (loading
            ? '加载中…'
            : error == null
            ? '暂无实例'
            : '实例加载失败');
    return Surface(
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
            onPressed: () => showInstancePicker(
              context,
              instances: instances,
              selected: selected,
              loading: loading,
              error: error,
              avatarUrl: avatarUrl,
              onSelect: onSelectInstance,
            ),
          ),
        ],
      ),
    );
  }
}

/// 横向 tab 条：选中胶囊 accentSoft 底 + primary 字，未选中 muted，超出可横向滚动
class _TaskTabStrip extends StatelessWidget {
  const _TaskTabStrip({
    required this.selected,
    required this.queue,
    required this.onSelect,
  });
  final TaskTab selected;
  final QueueInfo? queue;
  final ValueChanged<TaskTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final queue = this.queue;
    final tabs = <(TaskTab, String)>[
      (TaskTab.config, '任务配置'),
      (TaskTab.running, '运行中 ${queue?.running.length ?? 0}'),
      (TaskTab.pending, '队列中 ${queue?.pending.length ?? 0}'),
      (TaskTab.waiting, '等待中 ${queue?.waiting.length ?? 0}'),
      (TaskTab.liveLog, '实时日志'),
      (TaskTab.schedule, '调度设置'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _TaskTabChip(
              label: tabs[i].$2,
              selected: selected == tabs[i].$1,
              onTap: () => onSelect(tabs[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskTabChip extends StatelessWidget {
  const _TaskTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.primary : scheme.mutedForeground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}
