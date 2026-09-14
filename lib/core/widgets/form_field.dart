import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/theme.dart';

class NkasFieldLabel extends StatelessWidget {
  const NkasFieldLabel({required this.label, this.description, super.key});

  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
        ),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: theme.textTheme.muted.copyWith(height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// 标签始终在控件上方，不占用输入值或占位提示的位置。
class NkasField extends StatelessWidget {
  const NkasField({
    required this.label,
    required this.child,
    this.description,
    super.key,
  });

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label.isNotEmpty) ...[
        ExcludeSemantics(
          child: NkasFieldLabel(label: label, description: description),
        ),
        const SizedBox(height: 8),
      ],
      Semantics(
        label: label.isEmpty ? null : label,
        hint: description,
        child: child,
      ),
    ],
  );
}

/// 保留 Flutter 的输入、校验和键盘行为，集中管理所有表单的外观。
class NkasTextField extends StatelessWidget {
  const NkasTextField({
    required this.label,
    this.description,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    super.key,
  });

  final String label;
  final String? description;
  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return NkasField(
      label: label,
      description: description,
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        focusNode: focusNode,
        enabled: enabled,
        readOnly: readOnly,
        obscureText: obscureText,
        autofocus: autofocus,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        onTap: onTap,
        style: theme.textTheme.p.copyWith(
          fontSize: 14,
          height: 1.4,
          color: enabled
              ? theme.colorScheme.foreground
              : theme.colorScheme.mutedForeground,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          helperText: helperText,
          errorText: errorText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          enabled: enabled,
        ).applyDefaults(NkasInputStyle.decoration(theme.colorScheme)),
      ),
    );
  }
}
