import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/theme.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.text,
    this.size = 36,
    this.fontSize = 13,
    this.background,
    this.foreground,
    this.imageUrl,
  });
  final String text;
  final double size;
  final double fontSize;
  final Color? background;
  final Color? foreground;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? scheme.avatarBg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text(
              text,
              style: TextStyle(
                color: foreground ?? scheme.avatarText,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Text(
                  text,
                  style: TextStyle(
                    color: foreground ?? scheme.avatarText,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}
