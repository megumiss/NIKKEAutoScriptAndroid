import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/deploy_info.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/filter_chip.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/theme.dart';

const _deployWarning = '修改部署配置可能导致更新失败或程序无法启动，修改需要重启后生效，请谨慎操作。';

const _resetTemplates = <(String, String)>[
  ('intl', '默认（国际）'),
  ('cn', '大陆镜像'),
  ('docker-intl', 'Docker（国际）'),
  ('docker-cn', 'Docker（大陆）'),
];

class DeployPage extends StatefulWidget {
  const DeployPage({
    required this.connectionController,
    required this.accessGranted,
    super.key,
  });

  final ConnectionController connectionController;
  final bool accessGranted;

  @override
  State<DeployPage> createState() => _DeployPageState();
}

class _DeployPageState extends State<DeployPage> {
  DeployInfo? info;
  bool loading = false;
  bool resetting = false;
  String? error;
  String? loadedBaseUrl;
  String? savingKey;
  final overrides = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_connectionChanged);
    _connectionChanged();
  }

  @override
  void didUpdateWidget(covariant DeployPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionController != widget.connectionController) {
      oldWidget.connectionController.removeListener(_connectionChanged);
      widget.connectionController.addListener(_connectionChanged);
    }
    if (oldWidget.accessGranted != widget.accessGranted) {
      _connectionChanged();
    }
  }

  @override
  void dispose() {
    widget.connectionController.removeListener(_connectionChanged);
    super.dispose();
  }

  void _connectionChanged() {
    final connection = widget.connectionController.state;
    if (widget.accessGranted &&
        connection.phase == ConnectionPhase.connected &&
        loadedBaseUrl != connection.baseUrl &&
        !loading) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!widget.accessGranted ||
        widget.connectionController.state.phase != ConnectionPhase.connected) {
      return;
    }
    final baseUrl = widget.connectionController.state.baseUrl;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.connectionController.fetchDeploy();
      if (!mounted ||
          !widget.accessGranted ||
          widget.connectionController.state.baseUrl != baseUrl) {
        return;
      }
      setState(() {
        info = result;
        overrides.clear();
        loadedBaseUrl = baseUrl;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loadedBaseUrl = baseUrl;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Object? _effectiveValue(DeployField field) =>
      overrides.containsKey(field.key) ? overrides[field.key] : field.value;

  Future<void> _patch(DeployField field, Object? value) async {
    if (savingKey != null) return;
    setState(() => savingKey = field.key);
    try {
      final normalized = await widget.connectionController.patchDeploy(
        field.key,
        value,
      );
      if (!mounted) return;
      setState(() => overrides[field.key] = normalized);
    } catch (exception) {
      if (!mounted) return;
      setState(() => overrides.remove(field.key));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$exception')));
    } finally {
      if (mounted) setState(() => savingKey = null);
    }
  }

  Future<void> _confirmReset() async {
    var template = _resetTemplates.first.$1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('还原默认部署配置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择要还原到的模板，当前部署配置将被覆盖。'),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: template,
                onChanged: (value) {
                  if (value != null) setState(() => template = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in _resetTemplates)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.$2),
                        value: item.$1,
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ShadTheme.of(context).colorScheme.destructive,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('还原'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => resetting = true);
    try {
      await widget.connectionController.resetDeploy(template: template);
      if (!mounted) return;
      loadedBaseUrl = null;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已还原默认部署配置')));
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('还原失败：$exception')));
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 88),
      children: [
        const PageSubtitle('配置更新、工具路径与运行行为，改动即保存'),
        _WarningCard(
          resetting: resetting,
          onReset:
              widget.connectionController.state.phase ==
                  ConnectionPhase.connected
              ? _confirmReset
              : null,
        ),
        const SizedBox(height: 14),
        ..._buildBody(),
      ],
    );
  }

  List<Widget> _buildBody() {
    final theme = ShadTheme.of(context);
    final connected =
        widget.connectionController.state.phase == ConnectionPhase.connected;
    final data = info;
    if (data == null && loading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 36),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (data == null) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(
            children: [
              Text(
                !connected
                    ? '后端未连接'
                    : error == null
                    ? '暂无部署配置'
                    : '部署配置加载失败：$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.muted,
              ),
              if (connected) ...[
                const SizedBox(height: 10),
                SecondaryButton(
                  icon: LucideIcons.refreshCw,
                  label: '重新加载',
                  onPressed: () {
                    loadedBaseUrl = null;
                    unawaited(_load());
                  },
                ),
              ],
            ],
          ),
        ),
      ];
    }
    return [
      for (
        var groupIndex = 0;
        groupIndex < data.groups.length;
        groupIndex++
      ) ...[
        if (groupIndex > 0) const SizedBox(height: 14),
        _DeployGroupView(
          group: data.groups[groupIndex],
          savingKey: savingKey,
          valueOf: _effectiveValue,
          onPatch: _patch,
        ),
      ],
      if (data.groups.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Text('暂无部署配置', style: theme.textTheme.muted),
        ),
    ];
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.resetting, required this.onReset});

  final bool resetting;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Surface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.triangleAlert,
                size: 18,
                color: scheme.destructive,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _deployWarning,
                  style: TextStyle(
                    color: scheme.destructive,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NkasButton(
            icon: resetting ? LucideIcons.loaderCircle : LucideIcons.undo2,
            label: resetting ? '正在还原…' : '还原默认',
            onPressed: resetting ? null : onReset,
            background: scheme.destructive,
            foreground: scheme.destructiveForeground,
            shadow: NkasShadows.accent(
              scheme.destructive,
              Theme.of(context).brightness,
            ),
            minHeight: 34,
            radius: 10,
            horizontalPadding: 10,
          ),
        ],
      ),
    );
  }
}

class _DeployGroupView extends StatelessWidget {
  const _DeployGroupView({
    required this.group,
    required this.savingKey,
    required this.valueOf,
    required this.onPatch,
  });

  final DeployGroup group;
  final String? savingKey;
  final Object? Function(DeployField) valueOf;
  final Future<void> Function(DeployField, Object?) onPatch;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.name, style: theme.textTheme.h4),
        const SizedBox(height: 7),
        Surface(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (var index = 0; index < group.fields.length; index++) ...[
                if (index > 0) const Divider(height: 18),
                _DeployFieldView(
                  field: group.fields[index],
                  value: valueOf(group.fields[index]),
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

class _DeployFieldView extends StatelessWidget {
  const _DeployFieldView({
    required this.field,
    required this.value,
    required this.saving,
    required this.onPatch,
  });

  final DeployField field;
  final Object? value;
  final bool saving;
  final Future<void> Function(DeployField, Object?) onPatch;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (field.help.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(field.help, style: theme.textTheme.muted),
        ],
        for (final hint in field.hints) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tag(label: hint.tag),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hint.text,
                    style: theme.textTheme.muted.copyWith(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    switch (field.widget) {
      case 'checkbox':
        return Row(
          children: [
            Expanded(child: label),
            Switch(
              value: value == true,
              onChanged: saving ? null : (next) => onPatch(field, next),
            ),
          ],
        );
      case 'select':
        final current = field.options.firstWhere(
          (option) => option.value == value?.toString(),
          orElse: () => field.options.isEmpty
              ? DeployOption(value: value?.toString() ?? '', label: '暂无选项')
              : field.options.first,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: 7),
            FieldSelect(
              label: '',
              value: current.label,
              options: [
                for (final option in field.options)
                  FieldSelectOption(option.value, option.label),
              ],
              onChanged: saving
                  ? null
                  : (next) {
                      final option = field.options.firstWhere(
                        (item) => item.value == next,
                      );
                      onPatch(field, option.value);
                    },
            ),
          ],
        );
      case 'multiselect':
        final selected = value is List
            ? (value as List).map((item) => item.toString()).toSet()
            : const <String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: 7),
            if (field.options.isEmpty)
              Text('暂无实例可选', style: theme.textTheme.muted)
            else
              Wrap(
                runSpacing: 6,
                children: [
                  for (final option in field.options)
                    NkasFilterChip(
                      label: option.label,
                      active: selected.contains(option.value),
                      onTap: saving
                          ? null
                          : () {
                              final next = {...selected};
                              if (!next.remove(option.value)) {
                                next.add(option.value);
                              }
                              onPatch(field, [
                                for (final item in field.options)
                                  if (next.contains(item.value)) item.value,
                              ]);
                            },
                    ),
                ],
              ),
          ],
        );
      case 'priority':
        final selected = (value?.toString() ?? '')
            .split('>')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: 7),
            _PriorityControl(
              field: field,
              selected: selected,
              disabled: saving,
              onPatch: onPatch,
            ),
          ],
        );
      default:
        final number = field.widget == 'number';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(height: 7),
            _DeployInputField(
              key: ValueKey('${field.key}:$value'),
              initialValue: value?.toString() ?? '',
              number: number,
              enabled: !saving,
              onSubmit: (next) => onPatch(field, next),
            ),
          ],
        );
    }
  }
}

/// priority 控件（对齐 WebUI FieldPriority）：已选实例按执行顺序排列成 chips，
/// 带左移/右移/移除按钮，未选项通过「添加」下拉追加；提交 'a > b' 字符串
class _PriorityControl extends StatelessWidget {
  const _PriorityControl({
    required this.field,
    required this.selected,
    required this.disabled,
    required this.onPatch,
  });

  final DeployField field;
  final List<String> selected;
  final bool disabled;
  final Future<void> Function(DeployField, Object?) onPatch;

  void _update(List<String> next) => onPatch(field, next.join(' > '));

  String _labelOf(String token) {
    for (final option in field.options) {
      if (option.value == token) return option.label;
    }
    return token;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final remaining = [
      for (final option in field.options)
        if (!selected.contains(option.value)) option,
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < selected.length; index++)
          Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
            decoration: BoxDecoration(
              color: scheme.accentSoft,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.primary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _labelOf(selected[index]),
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _PriorityAction(
                  icon: LucideIcons.chevronLeft,
                  tooltip: '前移',
                  onTap: disabled || index == 0
                      ? null
                      : () {
                          final next = [...selected];
                          final item = next.removeAt(index);
                          next.insert(index - 1, item);
                          _update(next);
                        },
                ),
                _PriorityAction(
                  icon: LucideIcons.chevronRight,
                  tooltip: '后移',
                  onTap: disabled || index == selected.length - 1
                      ? null
                      : () {
                          final next = [...selected];
                          final item = next.removeAt(index);
                          next.insert(index + 1, item);
                          _update(next);
                        },
                ),
                _PriorityAction(
                  icon: LucideIcons.x,
                  tooltip: '移除',
                  onTap: disabled
                      ? null
                      : () {
                          final next = [...selected]..removeAt(index);
                          _update(next);
                        },
                ),
              ],
            ),
          ),
        if (!disabled && remaining.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: '添加实例',
            onSelected: (value) => _update([...selected, value]),
            itemBuilder: (context) => [
              for (final option in remaining)
                PopupMenuItem(value: option.value, child: Text(option.label)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: scheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.plus,
                    size: 12,
                    color: scheme.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '添加',
                    style: TextStyle(
                      color: scheme.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (selected.isEmpty && remaining.isEmpty)
          Text('暂无实例可选', style: theme.textTheme.muted),
      ],
    );
  }
}

class _PriorityAction extends StatelessWidget {
  const _PriorityAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            icon,
            size: 12,
            color: onTap == null
                ? scheme.mutedForeground.withValues(alpha: .4)
                : scheme.primary,
          ),
        ),
      ),
    );
  }
}

/// text/number 输入：提交或失焦时回调；清空回调 null（后端恢复默认值）
class _DeployInputField extends StatefulWidget {
  const _DeployInputField({
    required this.initialValue,
    required this.number,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });

  final String initialValue;
  final bool number;
  final bool enabled;
  final ValueChanged<Object?> onSubmit;

  @override
  State<_DeployInputField> createState() => _DeployInputFieldState();
}

class _DeployInputFieldState extends State<_DeployInputField> {
  late final TextEditingController controller;
  late final FocusNode focusNode;
  late String saved;

  @override
  void initState() {
    super.initState();
    saved = widget.initialValue;
    controller = TextEditingController(text: saved);
    focusNode = FocusNode()..addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant _DeployInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != saved && !focusNode.hasFocus) {
      saved = widget.initialValue;
      controller.text = saved;
    }
  }

  @override
  void dispose() {
    focusNode.removeListener(_focusChanged);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!focusNode.hasFocus) _submit();
  }

  void _submit() {
    final text = controller.text.trim();
    if (text == saved) return;
    saved = text;
    if (text.isEmpty) {
      widget.onSubmit(null);
    } else if (widget.number) {
      widget.onSubmit(int.tryParse(text) ?? text);
    } else {
      widget.onSubmit(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: widget.enabled,
      keyboardType: widget.number ? TextInputType.number : TextInputType.text,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(isDense: true),
    );
  }
}
