import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/deploy_info.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/config_input.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/multi_select.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/priority_control.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/core/widgets/toggle.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:nkas_mobile/features/deploy/security_entry_actions.dart';

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
  bool entryBusy = false;
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
        entryBusy = false;
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

  Future<bool> _patch(DeployField field, Object? value) async {
    if (savingKey != null ||
        (field.key == 'SecurityEntryEnabled' && entryBusy)) {
      return false;
    }
    setState(() => savingKey = field.key);
    try {
      if (field.key == 'SecurityEntryEnabled' && value == false) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('关闭安全入口'),
            content: const Text('关闭后，任何网络可达的客户端均可直接访问后端。确认关闭？'),
            actions: [
              TextButton(
                style: NkasActionStyle.compactButton,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return false;
      }
      final normalized = await widget.connectionController.patchDeploy(
        field.key,
        value,
      );
      if (!mounted) return false;
      setState(() => overrides[field.key] = normalized);
      return true;
    } catch (exception) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$exception')));
      return false;
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
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择要还原到的模板，当前部署配置将被覆盖；安全入口开关和密钥保持不变。'),
              const SizedBox(height: 8),
              FieldSelect(
                label: '部署模板',
                value: _resetTemplates
                    .firstWhere((item) => item.$1 == template)
                    .$2,
                selectedValue: template,
                options: [
                  for (final item in _resetTemplates)
                    FieldSelectOption(item.$1, item.$2),
                ],
                onChanged: (value) {
                  setState(() => template = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              style: NkasActionStyle.compactButton,
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
                  compact: true,
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
          controller: widget.connectionController,
          entryBusy: entryBusy,
          onEntryBusy: (value) {
            if (mounted) setState(() => entryBusy = value);
          },
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            minHeight: NkasActionStyle.compactHeight,
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
    required this.controller,
    required this.entryBusy,
    required this.onEntryBusy,
  });

  final DeployGroup group;
  final String? savingKey;
  final Object? Function(DeployField) valueOf;
  final Future<bool> Function(DeployField, Object?) onPatch;
  final ConnectionController controller;
  final bool entryBusy;
  final ValueChanged<bool> onEntryBusy;

  @override
  Widget build(BuildContext context) {
    final fields = group.fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupLabel(group.name),
        Surface(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                if (index > 0) const Divider(height: 18),
                _DeployFieldView(
                  field: fields[index],
                  value: valueOf(fields[index]),
                  saving:
                      savingKey == fields[index].key ||
                      (fields[index].key == 'SecurityEntryEnabled' &&
                          entryBusy),
                  onPatch: onPatch,
                ),
                if (fields[index].key == 'SecurityEntryEnabled' &&
                    valueOf(fields[index]) == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SecurityEntryActions(
                      key: ValueKey(controller.state.baseUrl),
                      controller: controller,
                      disabled: savingKey == fields[index].key,
                      onBusyChanged: onEntryBusy,
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
  final Future<bool> Function(DeployField, Object?) onPatch;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final options = [
      for (final option in field.options)
        FieldSelectOption(option.value, option.label),
    ];
    final Widget control;
    switch (field.widget) {
      case 'checkbox':
        control = Row(
          children: [
            Expanded(
              child: NkasFieldLabel(
                label: field.title,
                description: field.help,
              ),
            ),
            NkasSwitch(
              label: field.title,
              value: value == true,
              onChanged: saving ? null : (next) => onPatch(field, next),
            ),
          ],
        );
      case 'select':
        final current = field.options
            .where((option) => option.value == value?.toString())
            .firstOrNull;
        control = FieldSelect(
          label: field.title,
          description: field.help,
          value: current?.label ?? value?.toString() ?? '',
          selectedValue: value?.toString(),
          options: options,
          onChanged: saving ? null : (next) => onPatch(field, next),
        );
      case 'multiselect':
        final selected = value is List
            ? (value as List).map((item) => item.toString()).toSet()
            : const <String>{};
        control = FieldSelect(
          label: field.title,
          description: field.help,
          value: field.options
              .where((option) => selected.contains(option.value))
              .map((option) => option.label)
              .join('、'),
          onTap: saving || options.isEmpty
              ? null
              : () async {
                  final next = await showNkasMultiSelect(
                    context: context,
                    title: field.title,
                    options: options,
                    selected: selected,
                  );
                  if (next != null) {
                    onPatch(field, [
                      for (final option in field.options)
                        if (next.contains(option.value)) option.value,
                    ]);
                  }
                },
        );
      case 'priority':
        control = NkasField(
          label: field.title,
          description: field.help,
          child: NkasPriorityControl(
            value: value?.toString() ?? '',
            options: options,
            addLabel: '添加实例',
            emptyLabel: '暂无实例可选',
            onChanged: saving ? null : (next) => onPatch(field, next),
          ),
        );
      default:
        control = NkasConfigInput(
          key: ValueKey(field.key),
          label: field.title,
          description: field.help,
          initialValue: value?.toString() ?? '',
          number: field.widget == 'number',
          multiline: field.widget == 'textarea',
          enabled: !saving,
          onSubmit: (text) {
            final trimmed = text.trim();
            return onPatch(
              field,
              trimmed.isEmpty
                  ? null
                  : field.widget == 'number'
                  ? num.parse(trimmed)
                  : trimmed,
            );
          },
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        control,
        for (final hint in field.hints) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tag(label: hint.tag),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hint.text,
                  style: theme.textTheme.muted.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
