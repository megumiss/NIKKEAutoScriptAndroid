import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/theme.dart';

class NkasFilterChip extends StatelessWidget {
  const NkasFilterChip({super.key, required this.label, this.active = false});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.accentSoft : theme.colorScheme.card,
        border: Border.all(
          color: active ? theme.colorScheme.primary : theme.colorScheme.border,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.mutedForeground,
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}
