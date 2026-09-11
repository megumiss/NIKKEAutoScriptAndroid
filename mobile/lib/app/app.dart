import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/app/shell.dart';
import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';
import 'package:nkas_mobile/theme.dart';

class NkasMobileApp extends StatefulWidget {
  const NkasMobileApp({
    this.connectionController,
    this.enableRealtime = true,
    super.key,
  });

  final ConnectionController? connectionController;
  final bool enableRealtime;

  @override
  State<NkasMobileApp> createState() => _NkasMobileAppState();
}

class _NkasMobileAppState extends State<NkasMobileApp> {
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
        enableRealtime: widget.enableRealtime,
        onThemeModeChanged: (value) => setState(() => themeMode = value),
      ),
    );
  }
}
