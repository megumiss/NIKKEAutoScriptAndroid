import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/theme.dart';

enum LogKind { info, warn, error }

class LogLine extends StatelessWidget {
  const LogLine({
    super.key,
    required this.time,
    required this.level,
    required this.message,
    required this.kind,
    this.source,
  });
  final String time;
  final String level;
  final String? source;
  final String message;
  final LogKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    const mono = TextStyle(
      fontFamily: kDefaultFontFamilyMono,
      fontSize: 10.5,
      height: 1.75,
    );
    final (badgeColor, badgeBg, lineBg) = switch (kind) {
      LogKind.info => (
        scheme.logInfoText,
        scheme.accentSoft,
        Colors.transparent,
      ),
      LogKind.warn => (
        scheme.warning,
        scheme.logWarnBadgeBg,
        scheme.logWarnLineBg,
      ),
      LogKind.error => (
        scheme.destructive,
        scheme.logErrorBadgeBg,
        scheme.logErrorLineBg,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: lineBg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(time, style: mono.copyWith(color: scheme.logTime)),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 43,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  level,
                  textAlign: TextAlign.center,
                  style: mono.copyWith(
                    color: badgeColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          if (source != null) ...[
            const SizedBox(width: 5),
            SizedBox(
              width: 48,
              child: Text(
                source!,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: scheme.logSource),
              ),
            ),
          ],
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                color: kind == LogKind.info ? scheme.logText : badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
