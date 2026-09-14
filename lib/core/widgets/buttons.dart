import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/theme.dart';

/// 图标+文字按钮基座：单行 Row（mainAxisSize.min + 固定 5px 间距、垂直居中、
/// 绝不换行），紧凑外观与至少 48 的触控范围分开设置。
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
    this.minHeight = NkasActionStyle.minTapSize,
    this.radius = 11,
    this.horizontalPadding = 13,
    this.loading = false,
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
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final enabled = onPressed != null && !loading;
    final visualHeight = minHeight + (borderColor == null ? 0 : 2);
    final touchPadding = ((NkasActionStyle.minTapSize - visualHeight) / 2)
        .clamp(0.0, double.infinity);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled || loading ? 1 : .45,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: r,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: touchPadding),
              child: Ink(
                decoration: BoxDecoration(
                  color: background,
                  border: borderColor != null
                      ? Border.all(color: borderColor!)
                      : null,
                  borderRadius: r,
                  boxShadow: enabled ? shadow : null,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: NkasActionStyle.minTapSize,
                    minHeight: minHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: minHeight < NkasActionStyle.minTapSize ? 6 : 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (loading)
                          SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: foreground,
                            ),
                          )
                        else
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
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
    this.loading = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return NkasButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      loading: loading,
      background: scheme.primary,
      foreground: scheme.primaryForeground,
      shadow: NkasShadows.accent(scheme.primary, Theme.of(context).brightness),
      minHeight: NkasActionStyle.minTapSize,
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
    this.loading = false,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return NkasButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      loading: loading,
      background: scheme.secondaryButtonBg,
      foreground: scheme.secondaryButtonText,
      borderColor: scheme.secondaryButtonBorder,
      minHeight: compact
          ? NkasActionStyle.secondaryHeight
          : NkasActionStyle.minTapSize,
      horizontalPadding: compact ? 10 : 13,
    );
  }
}
