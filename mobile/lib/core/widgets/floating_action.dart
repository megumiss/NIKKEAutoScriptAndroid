import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/buttons.dart';

/// 页面底部悬浮主按钮（全宽 PrimaryButton + 主色投影），
/// 初始化页与控制连接页等独立操作页统一使用
class NkasFloatingAction extends StatelessWidget {
  const NkasFloatingAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      elevation: 8,
      shadowColor: scheme.primary.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          icon: icon,
          label: label,
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }
}
