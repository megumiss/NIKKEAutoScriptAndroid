import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/instance_select.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/queue_row.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tab_strip.dart';
import 'package:nkas_mobile/features/instances/live_log_panel.dart';
import 'package:nkas_mobile/theme.dart';

/// 实例详情页顶部横向 tab：运行中/队列中/等待中三段队列 + 实时日志
enum InstanceTab { running, pending, waiting, liveLog }

/// 实例页直接展示选中实例的详情：头部（实例下拉/启停）+ 横向 tab（队列三段、
/// 实时日志）。队列行点击跳转任务页对应配置；任务配置、调度设置在任务页。
class InstancesPage extends StatefulWidget {
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
    required this.onToggle,
    required this.onSelectInstance,
    required this.onOpenTask,
    required this.liveLogUri,
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
  final QueueInfo? queue;
  final bool queueLoading;
  final String? queueError;
  final bool running;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelectInstance;
  final ValueChanged<String> onOpenTask;
  final Uri liveLogUri;
  final bool accessGranted;

  @override
  State<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends State<InstancesPage> {
  InstanceTab tab = InstanceTab.running;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    final queue = widget.queue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('查看实例状态、任务队列与实时日志'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Row(
            children: [
              Expanded(
                child: InstanceSelect(
                  instances: widget.instances,
                  selected: widget.selected,
                  selectedInstance: widget.selectedInstance,
                  loading: widget.loading,
                  error: widget.error,
                  avatarUrl: widget.avatarUrl,
                  onSelect: widget.onSelectInstance,
                ),
              ),
              if (widget.selectedInstance != null) ...[
                const SizedBox(width: 8),
                PrimaryButton(
                  destructive: widget.running,
                  icon: widget.toggleLoading
                      ? LucideIcons.loaderCircle
                      : widget.running
                      ? LucideIcons.square
                      : LucideIcons.play,
                  label: widget.toggleLoading
                      ? '处理中…'
                      : widget.running
                      ? '停止'
                      : '启动',
                  onPressed: widget.onToggle,
                  compact: true,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 10, inset, 0),
          child: NkasTabStrip<InstanceTab>(
            tabs: [
              (InstanceTab.running, '运行中 ${queue?.running.length ?? 0}'),
              (InstanceTab.pending, '队列中 ${queue?.pending.length ?? 0}'),
              (InstanceTab.waiting, '等待中 ${queue?.waiting.length ?? 0}'),
              (InstanceTab.liveLog, '实时日志'),
            ],
            selected: tab,
            onSelect: (value) => setState(() => tab = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _tabContent(inset)),
      ],
    );
  }

  Widget _tabContent(double inset) {
    final scheme = ShadTheme.of(context).colorScheme;
    switch (tab) {
      case InstanceTab.liveLog:
        return Padding(
          key: const ValueKey(InstanceTab.liveLog),
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
      case InstanceTab.running:
        return _queueList(
          inset,
          tab,
          widget.queue?.running,
          scheme.success,
          LucideIcons.loaderCircle,
        );
      case InstanceTab.pending:
        return _queueList(
          inset,
          tab,
          widget.queue?.pending,
          scheme.primary,
          LucideIcons.listOrdered,
        );
      case InstanceTab.waiting:
        return _queueList(
          inset,
          tab,
          widget.queue?.waiting,
          scheme.mutedForeground,
          LucideIcons.clock3,
        );
    }
  }

  Widget _queueList(
    double inset,
    InstanceTab key,
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
                  onTap: () => widget.onOpenTask(
                    items[i].command.isEmpty ? items[i].name : items[i].command,
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
