import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/app/shell.dart';
import 'package:nkas_mobile_preview/theme.dart';

class NkasPreviewApp extends StatefulWidget {
  const NkasPreviewApp({super.key});

  @override
  State<NkasPreviewApp> createState() => _NkasPreviewAppState();
}

class _NkasPreviewAppState extends State<NkasPreviewApp> {
  ThemeMode themeMode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      debugShowCheckedModeBanner: false,
      theme: nkasThemeData(Brightness.light),
      darkTheme: nkasThemeData(Brightness.dark),
      themeMode: themeMode,
      home: NkasShell(
        themeMode: themeMode,
        onThemeModeChanged: (value) => setState(() => themeMode = value),
      ),
    );
  }
}
