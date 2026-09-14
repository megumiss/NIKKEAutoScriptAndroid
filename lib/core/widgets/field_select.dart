import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/theme.dart';

class FieldSelect extends StatefulWidget {
  const FieldSelect({
    super.key,
    required this.label,
    required this.value,
    this.description,
    this.selectedValue,
    this.semanticLabel,
    this.options = const [],
    this.onChanged,
    this.onTap,
    this.dense = false,
    this.compact = false,
  });
  final String label;
  final String value;
  final String? description;
  final String? selectedValue;
  final String? semanticLabel;
  final List<FieldSelectOption> options;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  /// Compresses the visual control while retaining a comfortable hit target.
  final bool dense;

  /// 工具栏使用较小的外观，保留完整的点击高度。
  final bool compact;

  @override
  State<FieldSelect> createState() => _FieldSelectState();
}

class _FieldSelectState extends State<FieldSelect> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final dense = widget.dense || widget.compact;
    final minHeight = widget.compact
        ? NkasActionStyle.compactHeight
        : NkasInputStyle.minHeight;
    final enabled =
        widget.onTap != null ||
        (widget.onChanged != null && widget.options.isNotEmpty);
    final selected =
        widget.selectedValue ??
        widget.options
            .where((option) => option.label == widget.value)
            .firstOrNull
            ?.value;
    final control = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: InputDecorator(
        isFocused: focused && enabled,
        decoration: InputDecoration(
          enabled: enabled,
          constraints: BoxConstraints(minHeight: minHeight),
          contentPadding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
              : dense
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
              : NkasInputStyle.padding,
        ).applyDefaults(NkasInputStyle.decoration(scheme)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.value.isEmpty ? '请选择' : widget.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.p.copyWith(
                  fontSize: dense ? 12 : 14,
                  color: enabled && widget.value.isNotEmpty
                      ? scheme.foreground
                      : scheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: widget.compact ? 14 : 16,
              color: scheme.mutedForeground,
            ),
          ],
        ),
      ),
    );
    final tapTarget = widget.compact
        ? Padding(
            padding: const EdgeInsets.symmetric(
              vertical:
                  (NkasActionStyle.minTapSize - NkasActionStyle.compactHeight) /
                  2,
            ),
            child: control,
          )
        : control;
    return NkasField(
      label: widget.label,
      description: widget.description,
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => focused = value),
        child: Semantics(
          label: widget.semanticLabel,
          button: true,
          enabled: enabled,
          child: widget.onTap != null
              ? InkWell(
                  onTap: widget.onTap,
                  borderRadius: NkasInputStyle.radius,
                  child: tapTarget,
                )
              : PopupMenuButton<String>(
                  enabled: enabled,
                  tooltip:
                      widget.semanticLabel ??
                      (widget.label.isEmpty ? '选择' : widget.label),
                  initialValue: selected,
                  onSelected: widget.onChanged,
                  position: PopupMenuPosition.under,
                  borderRadius: NkasInputStyle.radius,
                  color: scheme.popover,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: NkasInputStyle.radius,
                    side: BorderSide(color: scheme.border),
                  ),
                  itemBuilder: (context) => [
                    for (final option in widget.options)
                      PopupMenuItem(
                        value: option.value,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                style: theme.textTheme.p,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (option.value == selected)
                              Icon(
                                LucideIcons.check,
                                size: 16,
                                color: scheme.primary,
                              )
                            else
                              const SizedBox(width: 16),
                          ],
                        ),
                      ),
                  ],
                  child: tapTarget,
                ),
        ),
      ),
    );
  }
}

class FieldSelectOption {
  const FieldSelectOption(this.value, this.label);

  final String value;
  final String label;
}
