import 'package:flutter/material.dart';

import 'app_services.dart';
import 'settings/settings.dart';
import 'ui/app_shell.dart';

class MdViewerApp extends StatelessWidget {
  const MdViewerApp({super.key, required this.services});

  final AppServices services;

  static ThemeData _theme(Brightness brightness) => ThemeData(
        colorSchemeSeed: const Color(0xFF0969DA),
        brightness: brightness,
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) => MaterialApp(
          title: 'MDViewer',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: switch (services.settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          home: const AppShell(),
        ),
      ),
    );
  }
}
