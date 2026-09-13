import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/instance_picker.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tab_strip.dart';
import 'package:nkas_mobile/features/instances/schedule_panel.dart';
import 'package:nkas_mobile/features/instances/schema_panel.dart';
import 'package:nkas_mobile/theme.dart';

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
          child: NkasTabStrip<TaskTab>(
            tabs: const [
              (TaskTab.config, '任务配置'),
              (TaskTab.schedule, '调度设置'),
            ],
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
