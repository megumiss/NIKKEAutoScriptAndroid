import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/api/screenshot_frame.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/icon_box.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/features/instances/live_log_panel.dart';
import 'package:nkas_mobile/features/instances/schedule_panel.dart';
import 'package:nkas_mobile/features/instances/schema_panel.dart';
import 'package:nkas_mobile/theme.dart';

/// 实例页内部层级：多实例时先进列表层，点卡片进详情（dashboard）；
/// 任务配置/调度设置/实时日志是详情层之下的整页功能层。
/// 单实例时跳过列表层，一级页面直接是 dashboard。
enum InstanceLayer { list, dashboard, tasks, schedule, liveLogs }

class InstancesPage extends StatelessWidget {
  const InstancesPage({
    required this.selected,
    required this.selectedInstance,
    required this.instances,
    required this.loading,
    required this.toggleLoading,
    required this.error,
    required this.avatarUrl,
    required this.queues,
    required this.queueLoading,
    required this.queueError,
    required this.running,
    required this.layer,
    required this.onLayerChanged,
    required this.onToggle,
    required this.onToggleInstance,
    required this.loadQueueSnapshot,
    required this.fetchScreenshot,
    required this.onOpenScreen,
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
    required this.schema,
    required this.schemaLoading,
    required this.schemaError,
    required this.loadSchema,
    required this.patchConfig,
    required this.onSelectInstance,
    required this.liveLogUri,
    required this.onOpenTask,
    required this.initialTaskKey,
    required this.accessGranted,
    super.key,
  });
  final String selected;
  final InstanceInfo? selectedInstance;
  final List<InstanceInfo> instances;
  final bool loading;
  final bool toggleLoading;
  final String? error;
  final String? Function(InstanceInfo item) avatarUrl;
  final Map<String, QueueInfo> queues;
  final bool queueLoading;
  final String? queueError;
  final bool running;
  final InstanceLayer layer;
  final ValueChanged<InstanceLayer> onLayerChanged;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleInstance;
  final Future<void> Function(String name) loadQueueSnapshot;
  final Future<ScreenshotFrame?> Function(String name) fetchScreenshot;
  final VoidCallback onOpenScreen;
  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;
  final SchemaInfo? schema;
  final bool schemaLoading;
  final String? schemaError;
  final Future<void> Function() loadSchema;
  final Future<void> Function(String, Object?) patchConfig;
  final ValueChanged<String> onSelectInstance;
  final Uri liveLogUri;
  final ValueChanged<String> onOpenTask;
  final String? initialTaskKey;
  final bool accessGranted;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    // 单实例（或尚未加载出列表）时跳过列表层
    if (layer == InstanceLayer.list && instances.length > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
            child: const PageSubtitle('选择实例查看详情'),
          ),
          Expanded(
            child: _InstanceList(
              instances: instances,
              loading: loading,
              error: error,
              toggleLoading: toggleLoading,
              avatarUrl: avatarUrl,
              queues: queues,
              loadQueueSnapshot: loadQueueSnapshot,
              onOpen: onSelectInstance,
              onToggleInstance: onToggleInstance,
            ),
          ),
        ],
      );
    }
    if (layer == InstanceLayer.tasks ||
        layer == InstanceLayer.schedule ||
        layer == InstanceLayer.liveLogs) {
      final title = switch (layer) {
        InstanceLayer.tasks => '任务配置',
        InstanceLayer.schedule => '调度设置',
        _ => '实时日志',
      };
      final content = switch (layer) {
        InstanceLayer.tasks => ListView(
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
          children: [
            SchemaPanel(
              schema: schema,
              loading: schemaLoading,
              error: schemaError,
              onReload: loadSchema,
              onPatch: patchConfig,
              initialTaskKey: initialTaskKey,
            ),
          ],
        ),
        InstanceLayer.schedule => ListView(
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
          children: [
            SchedulePanel(
              key: ValueKey(selected),
              loadSchedule: loadSchedule,
              saveSchedule: saveSchedule,
              resetSchedule: resetSchedule,
            ),
          ],
        ),
        _ => Padding(
          padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
          child: SizedBox.expand(
            child: LiveLogPanel(
              key: ValueKey(selected),
              running: running,
              uri: liveLogUri,
              accessGranted: accessGranted,
            ),
          ),
        ),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LayerBackBar(
            title: title,
            inset: inset,
            onBack: () => onLayerChanged(InstanceLayer.dashboard),
          ),
          Expanded(child: content),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('管理实例任务、调度、画面和日志'),
        ),
        _DashboardHeader(
          selectedInstance: selectedInstance,
          loading: loading,
          error: error,
          avatarUrl: avatarUrl,
          running: running,
          toggleLoading: toggleLoading,
          showSwitcher: instances.length > 1,
          onToggle: onToggle,
          onShowPicker: () => _showInstancePicker(context),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
            children: [
              _QueueSummary(
                queue: queues[selected],
                loading: queueLoading,
                error: queueError,
                onOpenTask: onOpenTask,
              ),
              const SizedBox(height: 16),
              _ScreenThumb(
                key: ValueKey(selected),
                loadFrame: () => fetchScreenshot(selected),
                onOpen: onOpenScreen,
              ),
              const SizedBox(height: 16),
              _ManageEntries(onOpen: onLayerChanged),
            ],
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

/// 功能层（任务配置/调度设置/实时日志）顶部的返回条：返回箭头 + 标题
class _LayerBackBar extends StatelessWidget {
  const _LayerBackBar({
    required this.title,
    required this.inset,
    required this.onBack,
  });
  final String title;
  final double inset;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            tooltip: '返回实例',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstanceList extends StatefulWidget {
  const _InstanceList({
    required this.instances,
    required this.loading,
    required this.error,
    required this.toggleLoading,
    required this.avatarUrl,
    required this.queues,
    required this.loadQueueSnapshot,
    required this.onOpen,
    required this.onToggleInstance,
  });
  final List<InstanceInfo> instances;
  final bool loading;
  final String? error;
  final bool toggleLoading;
  final String? Function(InstanceInfo item) avatarUrl;
  final Map<String, QueueInfo> queues;
  final Future<void> Function(String name) loadQueueSnapshot;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggleInstance;

  @override
  State<_InstanceList> createState() => _InstanceListState();
}

class _InstanceListState extends State<_InstanceList> {
  final pendingQueueNames = <String>{};

  @override
  void initState() {
    super.initState();
    _ensureQueues();
  }

  @override
  void didUpdateWidget(covariant _InstanceList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureQueues();
  }

  void _ensureQueues() {
    for (final item in widget.instances) {
      if (!widget.queues.containsKey(item.name)) _loadQueue(item.name);
    }
  }

  void _loadQueue(String name) {
    if (!pendingQueueNames.add(name)) return;
    widget.loadQueueSnapshot(name).whenComplete(() {
      pendingQueueNames.remove(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    if (widget.loading && widget.instances.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.instances.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Text(widget.error == null ? '暂无实例' : '实例加载失败'),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
      children: [
        for (var i = 0; i < widget.instances.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _InstanceCard(
            item: widget.instances[i],
            queue: widget.queues[widget.instances[i].name],
            toggleLoading: widget.toggleLoading,
            imageUrl: widget.avatarUrl(widget.instances[i]),
            onTap: () => widget.onOpen(widget.instances[i].name),
            onToggle: () => widget.onToggleInstance(widget.instances[i].name),
          ),
        ],
      ],
    );
  }
}

class _InstanceCard extends StatelessWidget {
  const _InstanceCard({
    required this.item,
    required this.queue,
    required this.toggleLoading,
    required this.imageUrl,
    required this.onTap,
    required this.onToggle,
  });
  final InstanceInfo item;
  final QueueInfo? queue;
  final bool toggleLoading;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Avatar(
                      text: item.name.characters.first,
                      size: 38,
                      fontSize: 15,
                      background: scheme.accentSoft,
                      foreground: scheme.configIconText,
                      imageUrl: imageUrl,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Status(status: item.status),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.detail,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.muted,
                          ),
                        ],
                      ),
                    ),
                    CompactButton(
                      icon: toggleLoading
                          ? LucideIcons.loaderCircle
                          : item.isRunning
                          ? LucideIcons.square
                          : LucideIcons.play,
                      label: toggleLoading
                          ? '处理中'
                          : item.isRunning
                          ? '停止'
                          : '启动',
                      onPressed: toggleLoading ? null : onToggle,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 15,
                      color: scheme.mutedForeground,
                    ),
                  ],
                ),
                if (queue != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _QueueCount(
                        label: '运行',
                        count: queue!.running.length,
                        color: scheme.success,
                      ),
                      const SizedBox(width: 12),
                      _QueueCount(
                        label: '队列',
                        count: queue!.pending.length,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      _QueueCount(
                        label: '等待',
                        count: queue!.waiting.length,
                        color: scheme.mutedForeground,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueCount extends StatelessWidget {
  const _QueueCount({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Dot(color: color),
        const SizedBox(width: 5),
        Text(
          '$label $count',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.selectedInstance,
    required this.loading,
    required this.error,
    required this.avatarUrl,
    required this.running,
    required this.toggleLoading,
    required this.showSwitcher,
    required this.onToggle,
    required this.onShowPicker,
  });
  final InstanceInfo? selectedInstance;
  final bool loading;
  final String? error;
  final String? Function(InstanceInfo item) avatarUrl;
  final bool running;
  final bool toggleLoading;
  final bool showSwitcher;
  final VoidCallback onToggle;
  final VoidCallback onShowPicker;

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
    return Padding(
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
            if (showSwitcher)
              CompactButton(
                icon: LucideIcons.layers3,
                label: '切换',
                onPressed: onShowPicker,
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
    );
  }
}

class _QueueSummary extends StatelessWidget {
  const _QueueSummary({
    required this.queue,
    required this.loading,
    required this.error,
    required this.onOpenTask,
  });
  final QueueInfo? queue;
  final bool loading;
  final String? error;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    if (loading && queue == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 36),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (queue == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Text(error == null ? '暂无队列数据' : '队列加载失败'),
      );
    }
    final groups = [
      ('运行中', queue!.running, scheme.success, LucideIcons.loaderCircle),
      ('队列中', queue!.pending, scheme.primary, LucideIcons.listOrdered),
      ('等待中', queue!.waiting, scheme.mutedForeground, LucideIcons.clock3),
    ];
    return Surface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _QueueCount(
                  label: groups[i].$1,
                  count: groups[i].$2.length,
                  color: groups[i].$3,
                ),
              ],
            ],
          ),
          if (queue!.running.isEmpty &&
              queue!.pending.isEmpty &&
              queue!.waiting.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('暂无任务', style: theme.textTheme.muted),
            )
          else ...[
            for (final group in groups)
              if (group.$2.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Divider(height: 12),
                for (var i = 0; i < group.$2.length; i++)
                  _QueueRow(
                    name: group.$2[i].name,
                    detail: group.$2[i].command,
                    time: group.$2[i].nextRun,
                    color: group.$3,
                    icon: group.$4,
                    // The schema is keyed by the backend command, not the localized label.
                    onTap: () => onOpenTask(
                      group.$2[i].command.isEmpty
                          ? group.$2[i].name
                          : group.$2[i].command,
                    ),
                  ),
              ],
          ],
        ],
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
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

/// 详情层的画面缩略：进入时拉一帧（不轮询），点击跳转画面页
class _ScreenThumb extends StatefulWidget {
  const _ScreenThumb({
    required this.loadFrame,
    required this.onOpen,
    super.key,
  });

  final Future<ScreenshotFrame?> Function() loadFrame;
  final VoidCallback onOpen;

  @override
  State<_ScreenThumb> createState() => _ScreenThumbState();
}

class _ScreenThumbState extends State<_ScreenThumb> {
  ScreenshotFrame? frame;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.loadFrame();
      if (!mounted) return;
      setState(() {
        frame = value;
        loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: NkasColors.screenBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                clipBehavior: Clip.antiAlias,
                child: frame == null
                    ? Center(
                        child: Text(
                          loaded ? '暂无画面' : '正在获取画面…',
                          style: const TextStyle(
                            color: NkasColors.screenText,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : Image.memory(
                        frame!.bytes,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        gaplessPlayback: true,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.monitorPlay,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        '实时画面',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 15,
                      color: scheme.mutedForeground,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageEntries extends StatelessWidget {
  const _ManageEntries({required this.onOpen});
  final ValueChanged<InstanceLayer> onOpen;

  @override
  Widget build(BuildContext context) {
    const entries = [
      (
        InstanceLayer.tasks,
        '任务配置',
        '按后端 schema 配置任务参数',
        LucideIcons.listOrdered,
      ),
      (InstanceLayer.schedule, '调度设置', '周期、启用与下次运行', LucideIcons.calendarClock),
      (InstanceLayer.liveLogs, '实时日志', '查看实例运行输出', LucideIcons.scrollText),
    ];
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ManageRow(
              title: entries[i].$2,
              detail: entries[i].$3,
              icon: entries[i].$4,
              onTap: () => onOpen(entries[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
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
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: theme.textTheme.muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
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
}
