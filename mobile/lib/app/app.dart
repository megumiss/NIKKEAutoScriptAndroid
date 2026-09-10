import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/app/shell.dart';
import 'package:nkas_mobile_preview/core/api/api_client.dart';
import 'package:nkas_mobile_preview/core/connection/connection_controller.dart';
import 'package:nkas_mobile_preview/core/settings/backend_settings.dart';
import 'package:nkas_mobile_preview/theme.dart';

class NkasPreviewApp extends StatefulWidget {
  const NkasPreviewApp({this.connectionController, super.key});

  final ConnectionController? connectionController;

  @override
  State<NkasPreviewApp> createState() => _NkasPreviewAppState();
}

class _NkasPreviewAppState extends State<NkasPreviewApp> {
  ThemeMode themeMode = ThemeMode.light;
  late final ConnectionController connectionController;
  late final bool ownsConnectionController;

  @override
  void initState() {
    super.initState();
    ownsConnectionController = widget.connectionController == null;
    connectionController =
        widget.connectionController ??
        ConnectionController(
          api: ApiClient(),
          settings: SharedPreferencesBackendSettings(),
        );
    connectionController.initialize();
  }

  @override
  void dispose() {
    if (ownsConnectionController) {
      connectionController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      debugShowCheckedModeBanner: false,
      theme: nkasThemeData(Brightness.light),
      darkTheme: nkasThemeData(Brightness.dark),
      themeMode: themeMode,
      home: NkasShell(
        themeMode: themeMode,
        connectionController: connectionController,
        onThemeModeChanged: (value) => setState(() => themeMode = value),
      ),
    );
  }
}
