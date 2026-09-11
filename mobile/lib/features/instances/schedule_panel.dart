import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';

class SchedulePanel extends StatefulWidget {
  const SchedulePanel({
    required this.loadSchedule,
    required this.saveSchedule,
    required this.resetSchedule,
    super.key,
  });

  final Future<List<ScheduleTask>> Function() loadSchedule;
  final Future<void> Function(List<Map<String, dynamic>>) saveSchedule;
  final Future<void> Function() resetSchedule;

  @override
  State<SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends State<SchedulePanel> {
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
