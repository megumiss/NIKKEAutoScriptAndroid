import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nkas_mobile/theme.dart';

class SelectBox extends StatelessWidget {
  const SelectBox({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return InputDecorator(
      decoration: const InputDecoration(
        enabled: false,
      ).applyDefaults(NkasInputStyle.decoration(theme.colorScheme)),
      child: Text(label, style: theme.textTheme.p),
    );
  }
}
