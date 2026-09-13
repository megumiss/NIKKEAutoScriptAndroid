import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color,
    this.radius = 16,
    this.shadow,
    this.bordered = true,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  /// 默认无阴影（原型列表/卡片只有 1px 描边）；仅 Hero 显式传 brand 阴影
  final List<BoxShadow>? shadow;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.card,
        borderRadius: BorderRadius.circular(radius),
        border: bordered ? Border.all(color: theme.colorScheme.border) : null,
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}
