import 'package:flutter/material.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/widgets/instance_select.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/tab_strip.dart';
import 'package:nkas_mobile/features/instances/schedule_panel.dart';
import 'package:nkas_mobile/features/instances/schema_panel.dart';

/// 任务页顶部横向 tab：任务配置 + 调度设置（队列与实时日志在实例详情页）
enum TaskTab { config, schedule }

class TasksPage extends StatefulWidget {
  const TasksPage({
    required this.instances,
    required this.selected,
    required this.selectedInstance,
    required this.avatarUrl,
    required this.instancesLoading,
    required this.instancesError,
    required this.onSelectInstance,
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
    super.key,
  });

  final List<InstanceInfo> instances;
  final String selected;
  final InstanceInfo? selectedInstance;
  final String? Function(InstanceInfo item) avatarUrl;
  final bool instancesLoading;
  final String? instancesError;
  final ValueChanged<String> onSelectInstance;
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

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('任务配置与调度'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: InstanceSelect(
            instances: widget.instances,
            selected: widget.selected,
            selectedInstance: widget.selectedInstance,
            avatarUrl: widget.avatarUrl,
            loading: widget.instancesLoading,
            error: widget.instancesError,
            onSelect: widget.onSelectInstance,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 10, inset, 0),
          child: NkasTabStrip<TaskTab>(
            tabs: const [(TaskTab.config, '任务配置'), (TaskTab.schedule, '调度设置')],
            selected: tab,
            onSelect: (value) => setState(() => tab = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (tab) {
            TaskTab.config => ListView(
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
            ),
            TaskTab.schedule => ListView(
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
            ),
          },
        ),
      ],
    );
  }
}
