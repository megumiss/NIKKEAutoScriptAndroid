import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.actionIcon,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final String? action;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.h3),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: theme.textTheme.muted),
              ],
            ],
          ),
        ),
        if (action != null)
          actionIcon != null
              ? NkasButton(
                  icon: actionIcon!,
                  label: action!,
                  onPressed: onAction ?? () {},
                  background: theme.colorScheme.secondaryButtonBg,
                  foreground: theme.colorScheme.secondaryButtonText,
                  borderColor: theme.colorScheme.secondaryButtonBorder,
                  minHeight: 34,
                  radius: 10,
                  horizontalPadding: 10,
                )
              : GestureDetector(
                  onTap: onAction,
                  child: Text(
                    action!,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
      ],
    );
  }
}
