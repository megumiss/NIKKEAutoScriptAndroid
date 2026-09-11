import 'package:flutter/material.dart';

class IconBox extends StatelessWidget {
  const IconBox({
    super.key,
    required this.icon,
    required this.color,
    this.background,
  });
  final IconData icon;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    width: 29,
    height: 29,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(icon, size: 15, color: color),
  );
}
