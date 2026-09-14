import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';

/// 任务和部署配置的即时保存输入，失败时保留草稿供重试。
class NkasConfigInput extends StatefulWidget {
  const NkasConfigInput({
    required this.label,
    required this.initialValue,
    required this.onSubmit,
    this.description,
    this.enabled = true,
    this.number = false,
    this.multiline = false,
    super.key,
  });

  final String label;
  final String? description;
  final String initialValue;
  final Future<bool> Function(String) onSubmit;
  final bool enabled;
  final bool number;
  final bool multiline;

  @override
  State<NkasConfigInput> createState() => _NkasConfigInputState();
}

class _NkasConfigInputState extends State<NkasConfigInput> {
  late final TextEditingController controller;
  late final FocusNode focusNode;
  late String saved;
  bool submitting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    saved = widget.initialValue;
    controller = TextEditingController(text: saved);
    focusNode = FocusNode()..addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant NkasConfigInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      saved = widget.initialValue;
      if (!focusNode.hasFocus || submitting) controller.text = saved;
    }
  }

  @override
  void dispose() {
    focusNode.removeListener(_focusChanged);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!focusNode.hasFocus && !widget.multiline && error == null) _submit();
  }

  Future<void> _submit() async {
    final text = controller.text;
    if (!widget.enabled || submitting || text == saved) return;
    if (widget.number && text.trim().isNotEmpty) {
      final value = num.tryParse(text.trim());
      if (value == null || !value.isFinite) {
        setState(() => error = '请输入有效数字');
        return;
      }
    }
    setState(() {
      submitting = true;
      error = null;
    });
    var success = false;
    try {
      success = await widget.onSubmit(text);
    } catch (_) {
      success = false;
    } finally {
      if (mounted) {
        setState(() {
          submitting = false;
          if (success) {
            saved = controller.text;
          } else {
            error = '保存失败，请重试';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = controller.text != saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NkasTextField(
          label: widget.label,
          description: widget.description,
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled && !submitting,
          errorText: error,
          minLines: widget.multiline ? 3 : null,
          maxLines: widget.multiline ? 6 : 1,
          keyboardType: widget.number
              ? const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                )
              : widget.multiline
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction: widget.multiline
              ? TextInputAction.newline
              : TextInputAction.done,
          onChanged: (_) => setState(() => error = null),
          onSubmitted: (_) => _submit(),
          suffixIcon: widget.multiline
              ? null
              : IconButton(
                  tooltip: '保存${widget.label}',
                  onPressed: widget.enabled && !submitting && dirty
                      ? _submit
                      : null,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.check, size: 18),
                ),
        ),
        if (widget.multiline) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              compact: true,
              icon: LucideIcons.check,
              label: submitting ? '保存中…' : '保存',
              loading: submitting,
              onPressed: widget.enabled && dirty ? _submit : null,
            ),
          ),
        ],
      ],
    );
  }
}
