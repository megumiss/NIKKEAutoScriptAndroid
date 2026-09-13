import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/instance_picker.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/queue_row.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';

/// 实例页直接展示选中实例的详情：头部（切换/启停）+ 任务队列摘要。
/// 队列行点击跳转任务页对应配置；任务配置、实时日志、调度设置在任务页 tab 中。
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
    required this.onToggle,
    required this.onSelectInstance,
    required this.onOpenTask,
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
  final VoidCallback onToggle;
  final ValueChanged<String> onSelectInstance;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('查看实例状态与任务队列'),
        ),
        _DashboardHeader(
          selectedInstance: selectedInstance,
          loading: loading,
          error: error,
          avatarUrl: avatarUrl,
          running: running,
          toggleLoading: toggleLoading,
          showSwitcher: instances.isNotEmpty,
          onToggle: onToggle,
          onShowPicker: () => showInstancePicker(
            context,
            instances: instances,
            selected: selected,
            loading: loading,
            error: error,
            avatarUrl: avatarUrl,
            onSelect: onSelectInstance,
          ),
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
            ],
          ),
        ),
      ],
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

class _QueueSummary extends StatefulWidget {
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
  State<_QueueSummary> createState() => _QueueSummaryState();
}

class _QueueSummaryState extends State<_QueueSummary> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    if (widget.loading && widget.queue == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 36),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (widget.queue == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Text(widget.error == null ? '暂无队列数据' : '队列加载失败'),
      );
    }
    final groups = [
      ('运行中', widget.queue!.running, scheme.success, LucideIcons.loaderCircle),
      ('队列中', widget.queue!.pending, scheme.primary, LucideIcons.listOrdered),
      (
        '等待中',
        widget.queue!.waiting,
        scheme.mutedForeground,
        LucideIcons.clock3,
      ),
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
          if (widget.queue!.running.isEmpty &&
              widget.queue!.pending.isEmpty &&
              widget.queue!.waiting.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('暂无任务', style: theme.textTheme.muted),
            )
          else ...[
            for (final group in groups)
              if (group.$2.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Divider(height: 12),
                for (
                  var i = 0;
                  i <
                      (expanded
                          ? group.$2.length
                          : group.$2.length.clamp(0, 3));
                  i++
                )
                  QueueRow(
                    name: group.$2[i].name,
                    detail: group.$2[i].command,
                    time: group.$2[i].nextRun,
                    color: group.$3,
                    icon: group.$4,
                    // The schema is keyed by the backend command, not the localized label.
                    onTap: () => widget.onOpenTask(
                      group.$2[i].command.isEmpty
                          ? group.$2[i].name
                          : group.$2[i].command,
                    ),
                  ),
              ],
            if (groups.any((group) => group.$2.length > 3))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => expanded = !expanded),
                  icon: Icon(
                    expanded
                        ? LucideIcons.chevronsUp
                        : LucideIcons.chevronsDown,
                    size: 16,
                  ),
                  label: Text(expanded ? '收起队列' : '展开全部'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
