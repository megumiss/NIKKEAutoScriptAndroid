import 'package:flutter/material.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';

/// 键盘是否弹出。Scaffold 调整布局后会把 viewInsets 从页面 MediaQuery 中
/// 消费掉，需要从 View 直接读取（物理像素）
bool nkasKeyboardOpen(BuildContext context) {
  final view = View.of(context);
  return view.viewInsets.bottom / view.devicePixelRatio > 0;
}

/// 页面底部悬浮主按钮（全宽 PrimaryButton + 主色投影），
/// 初始化页与控制连接页等独立操作页统一使用
class NkasFloatingAction extends StatelessWidget {
  const NkasFloatingAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        icon: icon,
        label: label,
        loading: loading,
        onPressed: enabled ? onPressed : null,
      ),
    );
  }
}
