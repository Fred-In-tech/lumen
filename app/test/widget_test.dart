import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/features/home/home_screen.dart';

void main() {
  testWidgets('first run opens Home with one welcoming import card', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(
            MemoryCatalogRepository(),
          ),
          presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
        ],
        child: const LumenApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('developed.'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Choose photos'), findsOneWidget);
  });
}
