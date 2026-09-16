import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/theme.dart';

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

  /// 跨布局分支复用 content 的 Element，避免键盘切换时重建输入框
  final GlobalKey _contentKey = GlobalKey();

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
    // content 必须跨两个分支保持同一个 Element：父链在 Stack 与 Column
    // 之间切换时，框架会按「父级 + 位置」重新匹配，列表里正在编辑的
    // 输入框随之重建、FocusNode 丢失，键盘会立刻收起。固定 key 让框架
    // 复用同一个 Element（见测试 'keyboard open keeps the editing field'）
    final content = KeyedSubtree(key: _contentKey, child: widget.content);
    if (_keyboardOpen) {
      return Column(
        children: [
          Expanded(child: content),
          Padding(
            padding: EdgeInsets.fromLTRB(widget.inset, 8, widget.inset, 12),
            child: widget.action,
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
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
    // 禁用态保持实心：次级按钮配色本身带 alpha（原型 .np-secondary 是卡片内的
    // 行内按钮），直接用在悬浮按钮上会让下方滚动内容透出来，看起来像故障。
    // 只合成背景；边框保持原样，透明度不会造成内容穿透。
    if (!enabled && !loading) {
      final scheme = ShadTheme.of(context).colorScheme;
      return SizedBox(
        width: double.infinity,
        child: NkasButton(
          icon: icon,
          label: label,
          onPressed: null,
          background: _opaqueOnScaffold(context, scheme.secondaryButtonBg),
          foreground: scheme.secondaryButtonText,
          borderColor: scheme.secondaryButtonBorder,
          disabledOpacity: 1,
        ),
      );
    }
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

/// 把半透明配色按页面底色合成为不透明色。
///
/// 悬浮按钮下方是滚动内容而不是固定色块，直接使用带 alpha 的次级按钮配色会让
/// 内容透出来，看起来像按钮坏了。次级按钮原型（.np-secondary）本就是为卡片内
/// 的行内按钮设计的半透明底，行内使用没有问题，只有底部悬浮按钮需要合成。
Color _opaqueOnScaffold(BuildContext context, Color color) {
  if (color.a >= 1) return color;
  final scheme = ShadTheme.of(context).colorScheme;
  return Color.alphaBlend(color, scheme.background);
}
