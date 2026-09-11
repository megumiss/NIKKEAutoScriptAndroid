import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FieldSelect extends StatelessWidget {
  const FieldSelect({
    super.key,
    required this.label,
    required this.value,
    this.options = const [],
    this.onChanged,
    this.onTap,
  });
  final String label;
  final String value;
  final List<FieldSelectOption> options;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.muted),
        const SizedBox(height: 5),
        PopupMenuButton<String>(
          enabled: onTap == null && onChanged != null && options.isNotEmpty,
          onSelected: onChanged,
          itemBuilder: (context) => [
            for (final option in options)
              PopupMenuItem(value: option.value, child: Text(option.label)),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const Icon(LucideIcons.chevronDown, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FieldSelectOption {
  const FieldSelectOption(this.value, this.label);

  final String value;
  final String label;
}
