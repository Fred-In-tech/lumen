import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:lumen/ai/ondevice/ai_mask_providers.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/repositories.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen(
    (r) => debugPrint('${r.level.name} ${r.loggerName}: ${r.message}'),
  );
  final repos = await openRepositories();
  runApp(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repos.catalog),
        presetRepositoryProvider.overrideWithValue(repos.presets),
        settingsRepositoryProvider.overrideWithValue(repos.settings),
        aiMaskSourceProvider.overrideWith(
          (ref) => ref.watch(onDeviceAiMaskSourceProvider),
        ),
        aiMaskRasterLoaderProvider.overrideWith(
          (ref) => ref.watch(onDeviceAiMaskSourceProvider),
        ),
      ],
      child: const LumenApp(),
    ),
  );
}
