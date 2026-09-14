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
    return Semantics(
      button: true,
      selected: active,
      enabled: onTap != null,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: active
                  ? theme.colorScheme.accentSoft
                  : theme.colorScheme.card,
              foregroundColor: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
              disabledForegroundColor: theme.colorScheme.mutedForeground,
              shape: const StadiumBorder(),
              side: BorderSide(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.border,
              ),
              minimumSize: const Size(
                NkasActionStyle.minTapSize,
                NkasActionStyle.chipHeight,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
              textStyle: theme.textTheme.p.copyWith(
                fontFamily: theme.textTheme.family,
                fontSize: 12,
                height: 1.3,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
