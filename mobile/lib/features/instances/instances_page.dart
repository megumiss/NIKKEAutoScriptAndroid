import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/api/instance_info.dart';
import 'package:nkas_mobile_preview/core/api/queue_info.dart';
import 'package:nkas_mobile_preview/core/api/screenshot_frame.dart';
import 'package:nkas_mobile_preview/core/api/schedule_info.dart';
import 'package:nkas_mobile_preview/core/api/schema_info.dart';
import 'package:nkas_mobile_preview/core/connection/instance_log_socket.dart';
import 'package:nkas_mobile_preview/core/widgets/avatar.dart';
import 'package:nkas_mobile_preview/core/widgets/buttons.dart';
import 'package:nkas_mobile_preview/core/widgets/icon_box.dart';
import 'package:nkas_mobile_preview/core/widgets/field_select.dart';
import 'package:nkas_mobile_preview/core/widgets/log_line.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/status.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/core/widgets/tag.dart';
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
    required this.schema,
    required this.schemaLoading,
    required this.schemaError,
    required this.loadSchema,
    required this.patchConfig,
    required this.onSelectInstance,
    required this.onOpenControl,
    required this.liveLogUri,
    required this.onOpenTask,
    required this.initialTaskKey,
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
  final SchemaInfo? schema;
  final bool schemaLoading;
  final String? schemaError;
  final Future<void> Function() loadSchema;
  final Future<void> Function(String, Object?) patchConfig;
  final ValueChanged<String> onSelectInstance;
  final VoidCallback onOpenControl;
  final Uri liveLogUri;
  final ValueChanged<String> onOpenTask;
  final String? initialTaskKey;

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
            running: running,
            loadScreenshot: loadScreenshot,
            onOpenControl: onOpenControl,
            loadSchedule: loadSchedule,
            saveSchedule: saveSchedule,
            resetSchedule: resetSchedule,
            schema: schema,
            schemaLoading: schemaLoading,
            schemaError: schemaError,
            loadSchema: loadSchema,
            patchConfig: patchConfig,
            liveLogUri: liveLogUri,
            onOpenTask: onOpenTask,
            initialTaskKey: initialTaskKey,
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
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: nkasPageInset(context)),
          child: Row(
            children: [
              for (final item in items)
                InkWell(
                  onTap: () => onChanged(item.$1),
                  child: Container(
                    height: 48,
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
    required this.running,
    required this.loadScreenshot,
    required this.onOpenControl,
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
    required this.schema,
    required this.schemaLoading,
    required this.schemaError,
    required this.loadSchema,
    required this.patchConfig,
    required this.liveLogUri,
    required this.onOpenTask,
    required this.initialTaskKey,
  });
  final InstanceTab tab;
  final QueueInfo? queue;
  final bool loading;
  final String? error;
  final String selected;
  final bool running;
  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final VoidCallback onOpenControl;
  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;
  final SchemaInfo? schema;
  final bool schemaLoading;
  final String? schemaError;
  final Future<void> Function() loadSchema;
  final Future<void> Function(String, Object?) patchConfig;
  final Uri liveLogUri;
  final ValueChanged<String> onOpenTask;
  final String? initialTaskKey;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    final children = switch (tab) {
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
        else if (queue!.running.isEmpty &&
            queue!.pending.isEmpty &&
            queue!.waiting.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Text('暂无任务', style: ShadTheme.of(context).textTheme.muted),
          )
        else ...[
          if (queue!.running.isNotEmpty) ...[
            _QueueGroup.fromItems(
              label: '运行中',
              colorKind: 0,
              items: queue!.running,
              onTap: onOpenTask,
            ),
          ],
          if (queue!.pending.isNotEmpty) ...[
            if (queue!.running.isNotEmpty) const SizedBox(height: 16),
            _QueueGroup.fromItems(
              label: '队列中',
              colorKind: 1,
              items: queue!.pending,
              onTap: onOpenTask,
            ),
          ],
          if (queue!.waiting.isNotEmpty) ...[
            if (queue!.running.isNotEmpty || queue!.pending.isNotEmpty)
              const SizedBox(height: 16),
            _QueueGroup.fromItems(
              label: '等待中',
              colorKind: 2,
              items: queue!.waiting,
              onTap: onOpenTask,
            ),
          ],
        ],
      ],
      InstanceTab.tasks => [
        _SchemaPanel(
          schema: schema,
          loading: schemaLoading,
          error: schemaError,
          onReload: loadSchema,
          onPatch: patchConfig,
          initialTaskKey: initialTaskKey,
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
      InstanceTab.liveLogs => [const SizedBox.shrink()],
      InstanceTab.screen => [const SizedBox.shrink()],
    };
    if (tab == InstanceTab.liveLogs) {
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 8, inset, 78),
        child: SizedBox.expand(
          child: _LiveLogPanel(
            key: ValueKey(selected),
            running: running,
            uri: liveLogUri,
          ),
        ),
      );
    }
    if (tab == InstanceTab.screen) {
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 8, inset, 78),
        child: SizedBox.expand(
          child: _ScreenPanel(
            key: ValueKey(selected),
            loadScreenshot: loadScreenshot,
            onOpenControl: onOpenControl,
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
      children: children,
    );
  }
}

class _QueueGroup extends StatelessWidget {
  factory _QueueGroup.fromItems({
    required String label,
    required int colorKind,
    required List<QueueItem> items,
    required ValueChanged<String> onTap,
  }) => _QueueGroup(
    label: label,
    colorKind: colorKind,
    rows: [for (final item in items) (item.name, item.command, item.nextRun)],
    onTap: onTap,
  );

  const _QueueGroup({
    required this.label,
    required this.colorKind,
    required this.rows,
    required this.onTap,
  });
  final String label;
  final int colorKind;
  final List<(String, String, String)> rows;
  final ValueChanged<String> onTap;

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
                  // The schema is keyed by the backend command, not the localized label.
                  onTap: () =>
                      onTap(rows[i].$2.isEmpty ? rows[i].$1 : rows[i].$2),
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
    required this.onTap,
  });
  final String name;
  final String detail;
  final String time;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
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
        ),
      ),
    );
  }
}

class _SchemaPanel extends StatefulWidget {
  const _SchemaPanel({
    required this.schema,
    required this.loading,
    required this.error,
    required this.onReload,
    required this.onPatch,
    required this.initialTaskKey,
  });

  final SchemaInfo? schema;
  final bool loading;
  final String? error;
  final Future<void> Function() onReload;
  final Future<void> Function(String, Object?) onPatch;
  final String? initialTaskKey;

  @override
  State<_SchemaPanel> createState() => _SchemaPanelState();
}

class _SchemaPanelState extends State<_SchemaPanel> {
  String? taskKey;
  String? savingKey;

  @override
  void initState() {
    super.initState();
    taskKey = widget.initialTaskKey;
  }

  @override
  void didUpdateWidget(covariant _SchemaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTaskKey != widget.initialTaskKey) {
      taskKey = widget.initialTaskKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (widget.loading && widget.schema == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.schema == null) {
      return Column(
        children: [
          Text(widget.error == null ? '暂无任务配置' : '任务配置加载失败'),
          const SizedBox(height: 10),
          SecondaryButton(
            icon: LucideIcons.refreshCw,
            label: '重新加载',
            onPressed: widget.onReload,
          ),
        ],
      );
    }
    final schema = widget.schema!;
    final task = taskKey == null ? null : schema.tasks[taskKey];
    if (task != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => setState(() => taskKey = null),
                icon: const Icon(LucideIcons.arrowLeft, size: 19),
                tooltip: '返回任务列表',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (task.help.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(task.help, style: theme.textTheme.muted),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < task.groups.length; index++) ...[
            if (index > 0) const SizedBox(height: 14),
            _SchemaGroup(
              group: task.groups[index],
              savingKey: savingKey,
              onPatch: _patch,
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var menuIndex = 0;
          menuIndex < schema.menus.length;
          menuIndex++
        ) ...[
          if (menuIndex > 0) const SizedBox(height: 16),
          _SchemaMenuGroup(
            menu: schema.menus[menuIndex],
            icon: _menuIcon(menuIndex, schema.menus[menuIndex].name),
            onTask: (key) => setState(() => taskKey = key),
          ),
        ],
        if (schema.menus.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Text('暂无任务配置', style: theme.textTheme.muted),
          ),
      ],
    );
  }

  static IconData _menuIcon(int index, String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('活动')) return LucideIcons.calendarDays;
    if (normalized.contains('工具') || normalized.contains('设置')) {
      return LucideIcons.wrench;
    }
    return switch (index) {
      0 => LucideIcons.sun,
      1 => LucideIcons.calendarDays,
      _ => LucideIcons.wrench,
    };
  }

  Future<void> _patch(String key, Object? value) async {
    setState(() => savingKey = key);
    try {
      await widget.onPatch(key, value);
      await widget.onReload();
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$exception')));
      }
    } finally {
      if (mounted) setState(() => savingKey = null);
    }
  }
}

class _SchemaMenuGroup extends StatelessWidget {
  const _SchemaMenuGroup({
    required this.menu,
    required this.icon,
    required this.onTask,
  });
  final SchemaMenu menu;
  final IconData icon;
  final ValueChanged<String> onTask;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Text(
              menu.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < menu.tasks.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _SchemaTaskRow(
                  task: menu.tasks[index],
                  onTap: () => onTask(menu.tasks[index].key),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SchemaTaskRow extends StatelessWidget {
  const _SchemaTaskRow({required this.task, required this.onTap});
  final SchemaMenuTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final icon = _taskIcon(task.name);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconBox(icon: icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (task.help.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.help,
                          style: theme.textTheme.muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Tag(label: '已配置', color: theme.colorScheme.primary),
                const SizedBox(width: 5),
                Icon(
                  LucideIcons.chevronRight,
                  size: 15,
                  color: theme.colorScheme.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _taskIcon(String name) {
    if (name.contains('前哨')) return LucideIcons.home;
    if (name.contains('咨询')) return LucideIcons.messageCircle;
    if (name.contains('剧情') || name.contains('活动')) {
      return LucideIcons.scrollText;
    }
    if (name.contains('协同')) return LucideIcons.swords;
    if (name.contains('设备') || name.contains('通知')) {
      return LucideIcons.settings2;
    }
    return LucideIcons.listOrdered;
  }
}

class _SchemaGroup extends StatelessWidget {
  const _SchemaGroup({
    required this.group,
    required this.savingKey,
    required this.onPatch,
  });
  final SchemaGroup group;
  final String? savingKey;
  final Future<void> Function(String, Object?) onPatch;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.name, style: theme.textTheme.h4),
        if (group.help.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(group.help, style: theme.textTheme.muted),
        ],
        const SizedBox(height: 7),
        Surface(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (var index = 0; index < group.fields.length; index++) ...[
                if (index > 0) const Divider(height: 18),
                _SchemaFieldView(
                  field: group.fields[index],
                  saving: savingKey == group.fields[index].key,
                  onPatch: onPatch,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SchemaFieldView extends StatelessWidget {
  const _SchemaFieldView({
    required this.field,
    required this.saving,
    required this.onPatch,
  });
  final SchemaField field;
  final bool saving;
  final Future<void> Function(String, Object?) onPatch;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final disabled = field.readonly || saving;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (field.help.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(field.help, style: theme.textTheme.muted),
        ],
      ],
    );
    if (field.widget == 'checkbox') {
      return Row(
        children: [
          Expanded(child: label),
          Switch(
            value: field.value == true,
            onChanged: disabled ? null : (value) => onPatch(field.key, value),
          ),
        ],
      );
    }
    if (field.widget == 'select' || field.widget == 'multiselect') {
      final isMulti = field.widget == 'multiselect';
      final selectedValues = field.value is List
          ? (field.value as List).map((value) => value.toString()).toSet()
          : {field.value.toString()};
      final current = field.options.firstWhere(
        (option) => selectedValues.contains(option.value.toString()),
        orElse: () => field.options.isEmpty
            ? const SchemaOption(value: '', label: '暂无选项')
            : field.options.first,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: 7),
          FieldSelect(
            label: '',
            value: isMulti
                ? field.options
                      .where(
                        (option) =>
                            selectedValues.contains(option.value.toString()),
                      )
                      .map((option) => option.label)
                      .join('、')
                : current.label,
            options: [
              for (final option in field.options)
                FieldSelectOption(option.value.toString(), option.label),
            ],
            onChanged: disabled || isMulti
                ? null
                : (value) {
                    final option = field.options.firstWhere(
                      (item) => item.value.toString() == value,
                    );
                    onPatch(field.key, option.value);
                  },
            onTap: disabled || !isMulti
                ? null
                : () async {
                    final values = await _showMultiSelect(
                      context,
                      field.title,
                      field.options,
                      selectedValues,
                    );
                    if (values != null) onPatch(field.key, values);
                  },
          ),
        ],
      );
    }
    if (field.widget == 'datetime') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: 7),
          TextFormField(
            key: ValueKey('${field.key}:${field.value}'),
            initialValue: field.value?.toString() ?? '',
            enabled: !disabled,
            readOnly: true,
            onTap: disabled
                ? null
                : () async {
                    final initial = DateTime.tryParse(
                      field.value?.toString() ?? '',
                    )?.toLocal();
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      initialDate: initial ?? DateTime.now(),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: initial == null
                          ? TimeOfDay.now()
                          : TimeOfDay.fromDateTime(initial),
                    );
                    if (time == null) return;
                    final value = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    onPatch(field.key, _formatDateTimeLocal(value));
                  },
            decoration: const InputDecoration(
              suffixIcon: Icon(LucideIcons.calendarClock, size: 18),
            ),
          ),
        ],
      );
    }
    if (field.widget == 'input' || field.widget == 'textarea') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: 7),
          TextFormField(
            key: ValueKey('${field.key}:${field.value}'),
            initialValue: field.value?.toString() ?? '',
            enabled: !disabled,
            maxLines: field.widget == 'textarea' ? 4 : 1,
            onFieldSubmitted: (value) => onPatch(field.key, value),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 6),
        Text('该字段请通过原始 WebUI 操作', style: theme.textTheme.muted),
      ],
    );
  }

  static Future<List<Object?>?> _showMultiSelect(
    BuildContext context,
    String title,
    List<SchemaOption> options,
    Set<String> selected,
  ) async {
    final values = {...selected};
    return showModalBottomSheet<List<Object?>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ShadTheme.of(context).textTheme.h3),
                const SizedBox(height: 8),
                for (final option in options)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.label),
                    value: values.contains(option.value.toString()),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          values.add(option.value.toString());
                        } else {
                          values.remove(option.value.toString());
                        }
                      });
                    },
                  ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    icon: LucideIcons.check,
                    label: '完成',
                    onPressed: () => Navigator.pop(
                      context,
                      options
                          .where(
                            (option) =>
                                values.contains(option.value.toString()),
                          )
                          .map((option) => option.value)
                          .toList(growable: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDateTimeLocal(DateTime value) {
    String two(int item) => item.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}'
        'T${two(value.hour)}:${two(value.minute)}';
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
      padding: const EdgeInsets.all(10),
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
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: FieldSelect(
                  dense: true,
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
                  decoration: const InputDecoration(
                    labelText: '时间',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
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

class _LiveLogPanel extends StatefulWidget {
  const _LiveLogPanel({required this.running, required this.uri, super.key});

  final bool running;
  final Uri uri;

  @override
  State<_LiveLogPanel> createState() => _LiveLogPanelState();
}

class _LiveLogPanelState extends State<_LiveLogPanel> {
  String level = 'INFO';
  bool autoScroll = true;
  final scrollController = ScrollController();
  final lines = <_LiveLogLine>[];
  InstanceLogSocket? socket;
  Timer? reconnectTimer;
  bool connected = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void didUpdateWidget(covariant _LiveLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) unawaited(_connect());
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    unawaited(socket?.close());
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    reconnectTimer?.cancel();
    final previous = socket;
    socket = null;
    await previous?.close();
    if (!mounted) {
      return;
    }
    setState(() {
      connected = false;
      error = null;
      lines.clear();
    });
    final next = InstanceLogSocket(uri: widget.uri);
    socket = next;
    final connectedNow = await next.connect(
      onLog: _receive,
      onError: (_) {
        if (mounted) {
          setState(() {
            connected = false;
            error = '日志连接中断';
          });
        }
        _scheduleReconnect(next);
      },
      onClosed: () {
        if (mounted) setState(() => connected = false);
        _scheduleReconnect(next);
      },
    );
    if (mounted && socket == next && connectedNow) {
      setState(() => connected = true);
    }
  }

  void _scheduleReconnect(InstanceLogSocket source) {
    if (!mounted || socket != source) return;
    reconnectTimer?.cancel();
    reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => unawaited(_connect()),
    );
  }

  void _receive(InstanceLogEvent event) {
    if (!mounted) return;
    final parsed = event.html.expand(_parseFragment).toList(growable: false);
    if (parsed.isEmpty) return;
    setState(() {
      lines.addAll(parsed);
      if (lines.length > 500) lines.removeRange(0, lines.length - 500);
    });
    if (autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Iterable<_LiveLogLine> _parseFragment(String fragment) sync* {
    final lineMatch = RegExp(
      r'<div class="log-line([^>]*)">([\s\S]*?)</div>(?:<div class="log-traceback">([\s\S]*?)</div>)?',
    ).firstMatch(fragment);
    final content = lineMatch?.group(2) ?? fragment;
    final classes = lineMatch?.group(1) ?? '';
    final timestamp = _text(
      RegExp(
        r'<span class="ts">([\s\S]*?)</span>',
      ).firstMatch(content)?.group(1),
    );
    final levelText = _text(
      RegExp(
        r'<span class="lv-chip[^>]*>([\s\S]*?)</span>',
      ).firstMatch(content)?.group(1),
    );
    final message = _text(
      RegExp(
        r'<span class="log-message[^>]*>([\s\S]*?)</span>',
      ).firstMatch(content)?.group(1),
    ).trim();
    final fallback = _text(content).trim();
    final traceback = _text(lineMatch?.group(3)).trim();
    final value = message.isEmpty ? fallback : message;
    if (value.isEmpty) return;
    final kind =
        classes.contains('lv-err') ||
            levelText == 'ERROR' ||
            levelText == 'CRITICAL'
        ? LogKind.error
        : classes.contains('lv-warn') || levelText == 'WARNING'
        ? LogKind.warn
        : LogKind.info;
    yield _LiveLogLine(
      time: timestamp,
      level: levelText.isEmpty
          ? (classes.contains('section') ? 'INFO' : 'INFO')
          : levelText,
      message: value,
      kind: kind,
      traceback: traceback.isEmpty ? null : traceback,
    );
  }

  String _text(String? value) {
    if (value == null) return '';
    return value
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }

  bool _visible(_LiveLogLine line) {
    const ranks = {
      'DEBUG': 0,
      'INFO': 1,
      'WARNING': 2,
      'WARN': 2,
      'ERROR': 3,
      'CRITICAL': 3,
    };
    final selected = ranks[level] ?? 1;
    return (ranks[line.level] ?? 1) >= selected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.card,
              border: Border(bottom: BorderSide(color: scheme.border)),
            ),
            child: Row(
              children: [
                Icon(
                  widget.running ? LucideIcons.radio : LucideIcons.pauseCircle,
                  size: 16,
                  color: widget.running
                      ? scheme.success
                      : scheme.mutedForeground,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.running ? '实时日志' : '日志已暂停',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  initialValue: level,
                  tooltip: '实时日志级别',
                  onSelected: (value) => setState(() => level = value),
                  itemBuilder: (context) => [
                    for (final item in const ['DEBUG', 'INFO', 'WARN', 'ERROR'])
                      PopupMenuItem(value: item, child: Text(item)),
                  ],
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(level, style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.chevronDown, size: 14),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                _LiveToggle(
                  value: autoScroll,
                  onChanged: (value) => setState(() => autoScroll = value),
                ),
                const SizedBox(width: 6),
                Semantics(
                  label: connected ? '日志已连接' : '日志未连接',
                  child: Icon(
                    connected ? LucideIcons.wifi : LucideIcons.wifiOff,
                    size: 15,
                    color: connected ? scheme.success : scheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: scheme.logBodyBg,
              padding: const EdgeInsets.all(8),
              child: !connected && lines.isEmpty
                  ? Center(
                      child: Text(
                        error ?? '正在连接实时日志…',
                        style: theme.textTheme.muted,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: lines.where(_visible).length,
                      itemBuilder: (context, index) {
                        final visible = lines
                            .where(_visible)
                            .toList(growable: false);
                        final line = visible[index];
                        return LogLine(
                          time: line.time,
                          level: line.level,
                          message: line.message,
                          kind: line.kind,
                          traceback: line.traceback,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveLogLine {
  const _LiveLogLine({
    required this.time,
    required this.level,
    required this.message,
    required this.kind,
    this.traceback,
  });

  final String time;
  final String level;
  final String message;
  final LogKind kind;
  final String? traceback;
}

class _LiveToggle extends StatelessWidget {
  const _LiveToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: '自动滚动',
      child: Semantics(
        button: true,
        toggled: value,
        label: '自动滚动',
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 42,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? scheme.primary : scheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x24000000), blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenPanel extends StatefulWidget {
  const _ScreenPanel({
    required this.loadScreenshot,
    required this.onOpenControl,
    super.key,
  });

  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final VoidCallback onOpenControl;

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
    final controlLabel = frame == null ? '刷新画面' : '进入控制';
    return Surface(
      padding: EdgeInsets.zero,
      color: NkasColors.screenBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: frame == null
                  ? Center(
                      child: Text(
                        error == null
                            ? (loading ? '正在获取画面…' : '暂无画面')
                            : '画面加载失败',
                        style: const TextStyle(color: NkasColors.screenText),
                      ),
                    )
                  : Image.memory(
                      frame!.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              color: const Color(0xE0101D25),
              child: Row(
                children: [
                  Text(
                    frame == null ? '未连接' : _captureLabel(frame!.capturedAt),
                    style: const TextStyle(
                      color: Color(0xFFD6E3EA),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: loading
                        ? null
                        : frame == null
                        ? _load
                        : widget.onOpenControl,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      backgroundColor: const Color(0xFF2E4653),
                      foregroundColor: const Color(0xFFD6E3EA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: Text(
                      controlLabel,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
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
