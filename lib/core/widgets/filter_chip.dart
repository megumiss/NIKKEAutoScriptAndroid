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
    return Semantics(
      button: true,
      selected: active,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: active
                ? theme.colorScheme.accentSoft
                : theme.colorScheme.card,
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
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
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
