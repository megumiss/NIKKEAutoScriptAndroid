import 'package:flutter/material.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';

/// 键盘弹出时悬浮按钮会遮住正在编辑的输入框：键盘打开期间把
/// 按钮固定在列表下方，收起后恢复悬浮。Scaffold 调整布局后会把
/// viewInsets 从页面 MediaQuery 中消费掉（见 Scaffold 的
/// removeBottomInset），只能通过 didChangeMetrics 订阅键盘状态
class NkasKeyboardGuard extends StatefulWidget {
  const NkasKeyboardGuard({
    required this.content,
    required this.action,
    required this.inset,
    super.key,
  });

  final Widget content;
  final Widget action;
  final double inset;

  @override
  State<NkasKeyboardGuard> createState() => _NkasKeyboardGuardState();
}

class _NkasKeyboardGuardState extends State<NkasKeyboardGuard>
    with WidgetsBindingObserver {
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardOpen = _readKeyboardOpen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final open = _readKeyboardOpen();
    if (open != _keyboardOpen) {
      setState(() => _keyboardOpen = open);
    }
  }

  bool _readKeyboardOpen() {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio > 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_keyboardOpen) {
      return Column(
        children: [
          Expanded(child: widget.content),
          Padding(
            padding: EdgeInsets.fromLTRB(widget.inset, 8, widget.inset, 12),
            child: widget.action,
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: widget.content),
        Positioned(
          left: widget.inset,
          right: widget.inset,
          bottom: 12,
          child: widget.action,
        ),
      ],
    );
  }
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
