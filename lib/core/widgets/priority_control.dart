import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/theme.dart';

/// 有序多选保留原始选项值，以 WebUI 的 `A > B` 格式提交。
class NkasPriorityControl extends StatelessWidget {
  const NkasPriorityControl({
    required this.value,
    required this.options,
    required this.onChanged,
    this.addLabel = '添加选项',
    this.emptyLabel = '暂无可选项',
    super.key,
  });

  final String value;
  final List<FieldSelectOption> options;
  final ValueChanged<String>? onChanged;
  final String addLabel;
  final String emptyLabel;

  void _update(List<String> next) => onChanged?.call(next.join(' > '));

  String _labelOf(String token) =>
      options.where((option) => option.value == token).firstOrNull?.label ??
      token;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final disabled = onChanged == null;
    final selected = value
        .split('>')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final remaining = options
        .where((option) => !selected.contains(option.value))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < selected.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: scheme.input,
              borderRadius: NkasInputStyle.radius,
              border: Border.all(color: scheme.border),
            ),
            child: Row(
              children: [
                Text(
                  '${index + 1}',
                  style: theme.textTheme.p.copyWith(color: scheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _labelOf(selected[index]),
                    style: theme.textTheme.p,
                  ),
                ),
                IconButton(
                  tooltip: '前移',
                  style: NkasActionStyle.compactButton,
                  icon: const Icon(LucideIcons.chevronLeft, size: 15),
                  onPressed: disabled || index == 0
                      ? null
                      : () {
                          final next = [...selected];
                          final item = next.removeAt(index);
                          next.insert(index - 1, item);
                          _update(next);
                        },
                ),
                IconButton(
                  tooltip: '后移',
                  style: NkasActionStyle.compactButton,
                  icon: const Icon(LucideIcons.chevronRight, size: 15),
                  onPressed: disabled || index == selected.length - 1
                      ? null
                      : () {
                          final next = [...selected];
                          final item = next.removeAt(index);
                          next.insert(index + 1, item);
                          _update(next);
                        },
                ),
                IconButton(
                  tooltip: '移除',
                  color: scheme.destructive,
                  style: NkasActionStyle.compactButton,
                  icon: const Icon(LucideIcons.x, size: 15),
                  onPressed: disabled
                      ? null
                      : () => _update([...selected]..removeAt(index)),
                ),
              ],
            ),
          ),
        ],
        if (remaining.isNotEmpty) ...[
          if (selected.isNotEmpty) const SizedBox(height: 12),
          FieldSelect(
            label: addLabel,
            value: '',
            options: remaining,
            onChanged: disabled
                ? null
                : (value) => _update([...selected, value]),
          ),
        ],
        if (selected.isEmpty && remaining.isEmpty)
          Text(emptyLabel, style: theme.textTheme.muted),
      ],
    );
  }
}
