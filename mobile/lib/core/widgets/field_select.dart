import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FieldSelect extends StatelessWidget {
  const FieldSelect({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.muted),
        const SizedBox(height: 5),
        Container(
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
      ],
    );
  }
}
