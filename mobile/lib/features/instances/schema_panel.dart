import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/icon_box.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';

class SchemaPanel extends StatefulWidget {
  const SchemaPanel({
    required this.schema,
    required this.loading,
    required this.error,
    required this.onReload,
    required this.onPatch,
    required this.initialTaskKey,
    required this.onBack,
    required this.onTaskKeyChanged,
    super.key,
  });

  final SchemaInfo? schema;
  final bool loading;
  final String? error;
  final Future<void> Function() onReload;
  final Future<void> Function(String, Object?) onPatch;
  final String? initialTaskKey;
  final VoidCallback onBack;
  final ValueChanged<String?> onTaskKeyChanged;

  @override
  State<SchemaPanel> createState() => _SchemaPanelState();
}

class _SchemaPanelState extends State<SchemaPanel> {
  String? taskKey;
  String? savingKey;

  @override
  void initState() {
    super.initState();
    taskKey = widget.initialTaskKey;
  }

  @override
  void didUpdateWidget(covariant SchemaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTaskKey != widget.initialTaskKey) {
      taskKey = widget.initialTaskKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (widget.loading && widget.schema == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _taskListHeader(),
          const Padding(
            padding: EdgeInsets.only(top: 36),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (widget.schema == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _taskListHeader(),
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
                onPressed: () {
                  setState(() => taskKey = null);
                  widget.onTaskKeyChanged(null);
                },
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
        _taskListHeader(),
        for (
          var menuIndex = 0;
          menuIndex < schema.menus.length;
          menuIndex++
        ) ...[
          if (menuIndex > 0) const SizedBox(height: 16),
          _SchemaMenuGroup(
            menu: schema.menus[menuIndex],
            icon: _menuIcon(menuIndex, schema.menus[menuIndex].name),
            onTask: (key) {
              setState(() => taskKey = key);
              widget.onTaskKeyChanged(key);
            },
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

  Widget _taskListHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: widget.onBack,
          icon: const Icon(LucideIcons.arrowLeft, size: 19),
          tooltip: '返回实例',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        ),
        const SizedBox(width: 5),
        const Text(
          '任务配置',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
