import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class Tag extends StatelessWidget {
  const Tag({super.key, required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? ShadTheme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: resolved,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
