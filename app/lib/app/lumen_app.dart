import 'package:flutter/material.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/theme.dart';
import 'package:lumen/features/library/library_screen.dart';

/// Root widget. Navigation is a simple stack: Library → Editor.
class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kBrand.name,
      debugShowCheckedModeBanner: false,
      theme: buildLumenTheme(),
      darkTheme: buildLumenTheme(),
      themeMode: ThemeMode.dark,
      home: const LibraryScreen(),
    );
  }
}
