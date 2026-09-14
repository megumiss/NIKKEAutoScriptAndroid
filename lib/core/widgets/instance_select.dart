import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/theme.dart';

/// 实例、任务和画面页共用的实例下拉选择器。
class InstanceSelect extends StatefulWidget {
  const InstanceSelect({
    super.key,
    required this.instances,
    required this.selected,
    required this.selectedInstance,
    required this.loading,
    required this.error,
    required this.avatarUrl,
    required this.onSelect,
  });

  final List<InstanceInfo> instances;
  final String selected;
  final InstanceInfo? selectedInstance;
  final bool loading;
  final String? error;
  final String? Function(InstanceInfo item) avatarUrl;
  final ValueChanged<String> onSelect;

  @override
  State<InstanceSelect> createState() => _InstanceSelectState();
}

class _InstanceSelectState extends State<InstanceSelect> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final enabled = widget.instances.isNotEmpty;
    final current = widget.selectedInstance;
    final displayName =
        current?.name ??
        (widget.loading
            ? '加载中…'
            : widget.error == null
            ? '暂无实例'
            : '实例加载失败');

    return LayoutBuilder(
      builder: (context, constraints) => Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => focused = value),
        child: Theme(
          data: Theme.of(context).copyWith(highlightColor: scheme.accentSoft),
          child: Semantics(
            label: '选择实例',
            button: true,
            enabled: enabled,
            child: PopupMenuButton<String>(
              tooltip: '选择实例',
              enabled: enabled,
              initialValue: widget.selected,
              onSelected: (value) {
                if (value != widget.selected) widget.onSelect(value);
              },
              position: PopupMenuPosition.under,
              elevation: 0,
              offset: const Offset(0, 4),
              borderRadius: NkasInputStyle.radius,
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                maxHeight: MediaQuery.sizeOf(context).height * .6,
              ),
              itemBuilder: (context) => [
                for (final item in widget.instances)
                  PopupMenuItem<String>(
                    value: item.name,
                    height: NkasInputStyle.minHeight,
                    child: _InstanceValue(
                      label: item.name,
                      instance: item,
                      imageUrl: widget.avatarUrl(item),
                      maxLines: 2,
                      trailing: item.name == widget.selected
                          ? Icon(
                              LucideIcons.check,
                              size: 16,
                              color: scheme.primary,
                            )
                          : const SizedBox(width: 16),
                    ),
                  ),
              ],
              child: InputDecorator(
                isFocused: focused && enabled,
                decoration: InputDecoration(
                  enabled: enabled,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ).applyDefaults(NkasInputStyle.decoration(scheme)),
                child: _InstanceValue(
                  label: displayName,
                  instance: current,
                  imageUrl: current == null ? null : widget.avatarUrl(current),
                  trailing: Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: scheme.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstanceValue extends StatelessWidget {
  const _InstanceValue({
    required this.label,
    required this.instance,
    required this.imageUrl,
    required this.trailing,
    this.maxLines = 1,
  });

  final String label;
  final InstanceInfo? instance;
  final String? imageUrl;
  final Widget trailing;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        ExcludeSemantics(
          child: Avatar(
            text: instance?.name.characters.firstOrNull ?? '实',
            size: 32,
            fontSize: 14,
            imageUrl: imageUrl,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.p.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: instance == null
                      ? theme.colorScheme.mutedForeground
                      : theme.colorScheme.foreground,
                ),
              ),
              if (instance != null) ...[
                const SizedBox(height: 2),
                Status(status: instance!.status),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    );
  }
}
