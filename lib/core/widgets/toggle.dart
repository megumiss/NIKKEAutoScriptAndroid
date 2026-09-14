import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 胶囊开关（原型规格：42x24 轨道、18px 圆形滑块、150ms 滑动动画），
/// 设置页与各子页面统一使用，替代风格不一的 SwitchListTile
class NkasSwitch extends StatelessWidget {
  const NkasSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;

  /// null 表示禁用（不可切换）
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final onChanged = this.onChanged;
    return Semantics(
      button: true,
      enabled: onChanged != null,
      toggled: value,
      label: '$label，${value ? '已开启' : '已关闭'}',
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: Opacity(
          opacity: onChanged == null ? .45 : 1,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 42,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? scheme.primary : scheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: scheme.primaryForeground,
                      shape: BoxShape.circle,
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
