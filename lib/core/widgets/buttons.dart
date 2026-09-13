import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/theme.dart';

/// 图标+文字按钮基座：单行 Row（mainAxisSize.min + 固定 5px 间距、垂直居中、
/// 绝不换行），规格对齐原型 .np-primary/.np-secondary（min-height 38、圆角 11、
/// 字号 13、字重 600、图标 15、padding 0 13；紧凑档 min-height 34、圆角 10）。
class NkasButton extends StatelessWidget {
  const NkasButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.iconColor,
    this.borderColor,
    this.shadow,
    this.minHeight = 38,
    this.radius = 11,
    this.horizontalPadding = 13,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final Color? iconColor;
  final Color? borderColor;
  final List<BoxShadow>? shadow;
  final double minHeight;
  final double radius;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        borderRadius: r,
        boxShadow: shadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: r,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: iconColor ?? foreground),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return NkasButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      background: scheme.primary,
      foreground: scheme.primaryForeground,
      shadow: NkasShadows.accent(scheme.primary, Theme.of(context).brightness),
      minHeight: compact ? 34 : 38,
      radius: compact ? 10 : 11,
      horizontalPadding: compact ? 10 : 13,
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return NkasButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      background: scheme.secondaryButtonBg,
      foreground: scheme.secondaryButtonText,
      borderColor: scheme.secondaryButtonBorder,
    );
  }
}

/// 实例头部「切换」胶囊（原型 .np-instance-switcher）：#f8fbfc 底、1px line
/// 描边、圆角 10、min-height 34、蓝色 15px 图标
class CompactButton extends StatelessWidget {
  const CompactButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return NkasButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      background: scheme.switcherBg,
      foreground: scheme.foreground,
      iconColor: scheme.configIconText,
      borderColor: scheme.border,
      minHeight: 34,
      radius: 10,
      horizontalPadding: 10,
    );
  }
}
