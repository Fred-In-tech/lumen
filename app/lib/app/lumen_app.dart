import 'package:flutter/material.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/theme.dart';
import 'package:lumen/features/shell/app_shell.dart';

/// Root widget. The app shell (Home, Projects, a project, All photos,
/// Looks) with the editor pushed on top.
class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kBrand.name,
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(),
      themeMode: ThemeMode.light,
      home: const AppShell(),
    );
  }
}
