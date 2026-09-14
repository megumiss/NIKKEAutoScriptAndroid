import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/filter_chip.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/toggle.dart';

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
  final form = GlobalKey<FormState>();
  int revision = 0;

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
      if (mounted) {
        setState(() {
          tasks = value;
          revision++;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save(List<Map<String, dynamic>> changes) async {
    if (saving || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
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
    return Form(
      key: form,
      child: Column(
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
                key: ValueKey('${tasks[i].command}:$revision'),
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
                        nextRun: change['next_run']?.toString() ?? next.nextRun,
                        dailyTimes:
                            change['daily_times']?.toString() ??
                            next.dailyTimes,
                        weeklyDays:
                            change['weekly_days']?.toString() ??
                            next.weeklyDays,
                        weeklyTime:
                            change['weekly_time']?.toString() ??
                            next.weeklyTime,
                        monthlyDay:
                            change['monthly_day']?.toString() ??
                            next.monthlyDay,
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
                    loading: saving,
                    onPressed: saving
                        ? null
                        : () => _save([
                            for (final task in tasks)
                              {
                                'command': task.command,
                                'enable': task.enabled,
                                'cadence': task.cadence,
                                'next_run': task.nextRun,
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
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(
                color: ShadTheme.of(context).colorScheme.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.task,
    required this.disabled,
    required this.onChanged,
    super.key,
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
                    if (task.nextRun.isNotEmpty)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '下次运行：${task.nextRun}',
                              style: theme.textTheme.muted,
                            ),
                          ),
                          IconButton(
                            onPressed: disabled || task.locked
                                ? null
                                : () => onChanged({'next_run': ''}),
                            icon: const Icon(LucideIcons.x, size: 15),
                            tooltip: '立即执行',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 28,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              NkasSwitch(
                label: '启用',
                value: task.enabled,
                onChanged: disabled || task.enableLocked
                    ? null
                    : (value) => onChanged({'enable': value}),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FieldSelect(
                  label: '周期',
                  value: _cadenceLabel(task.cadence),
                  selectedValue: task.cadence,
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
              const SizedBox(width: 8),
              Expanded(
                child: NkasTextField(
                  key: ValueKey('${task.command}-${task.cadence}'),
                  label: '时间',
                  initialValue: task.activeTime,
                  enabled: !disabled && !task.locked,
                  hintText: '05:00',
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) {
                    onChanged({_activeTimeKey(task.cadence): value});
                  },
                ),
              ),
            ],
          ),
          if (task.cadence == 'weekly') ...[
            const SizedBox(height: 6),
            _WeekdayPicker(
              value: task.weeklyDays,
              disabled: disabled || task.locked,
              onChanged: (value) => onChanged({'weekly_days': value}),
            ),
          ],
          if (task.cadence == 'monthly') ...[
            const SizedBox(height: 12),
            NkasTextField(
              key: ValueKey('${task.command}-monthly-day'),
              label: '每月执行日',
              initialValue: task.monthlyDay,
              enabled: !disabled && !task.locked,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              hintText: '1–31',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              validator: (value) {
                if (disabled || task.locked) return null;
                final day = int.tryParse(value ?? '');
                return day == null || day < 1 || day > 31
                    ? '请输入 1–31 之间的日期'
                    : null;
              },
              onChanged: (value) => onChanged({'monthly_day': value}),
            ),
          ],
        ],
      ),
    );
  }

  static String _cadenceLabel(String value) => switch (value) {
    'weekly' => '每周',
    'monthly' => '每月',
    _ => '每天',
  };

  static String _activeTimeKey(String cadence) => switch (cadence) {
    'weekly' => 'weekly_time',
    'monthly' => 'monthly_time',
    _ => 'daily_times',
  };
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  final String value;
  final bool disabled;
  final ValueChanged<String> onChanged;

  static const days = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final selected = value
        .split(',')
        .map((item) => int.tryParse(item.trim()))
        .whereType<int>()
        .where((item) => item >= 1 && item <= 7)
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NkasFieldLabel(label: '执行日'),
        const SizedBox(height: 8),
        Wrap(
          runSpacing: 8,
          children: [
            for (var index = 0; index < days.length; index++)
              NkasFilterChip(
                label: '周${days[index]}',
                active: selected.contains(index + 1),
                onTap: disabled ? null : () => _toggle(selected, index + 1),
              ),
          ],
        ),
      ],
    );
  }

  void _toggle(Set<int> selected, int day) {
    final next = {...selected};
    if (next.contains(day)) {
      if (next.length <= 1) return;
      next.remove(day);
    } else {
      next.add(day);
    }
    onChanged((next.toList()..sort()).join(', '));
  }
}
