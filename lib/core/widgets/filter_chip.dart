import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/theme.dart';

class NkasFilterChip extends StatelessWidget {
  const NkasFilterChip({
    super.key,
    required this.label,
    this.active = false,
    this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final radius = BorderRadius.circular(999);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? theme.colorScheme.accentSoft : theme.colorScheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
