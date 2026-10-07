import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:uuid/uuid.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/looks/inflate.dart';
import 'package:lumen/import/folder_expansion.dart';
import 'package:lumen/platform/background.dart';

/// Where preset and LUT files come from. Swapped for a fake in tests.
abstract interface class LookImportSource {
  /// Opens the picker (multi-select); empty when cancelled.
  Future<List<LookImportFile>> pick();
}

class PickerLookImportSource implements LookImportSource {
  const PickerLookImportSource();

  @override
  Future<List<LookImportFile>> pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose presets or LUTs',
      type: FileType.custom,
      allowedExtensions: kLookFileExtensions,
    );
    return readLookXFiles([for (final f in files) f.xFile]);
  }
}

final lookImportSourceProvider = Provider<LookImportSource>(
  (ref) => const PickerLookImportSource(),
);

/// Reads dropped or picked preset / LUT files (folders expanded). Files of
/// other kinds are left out; oversized ones are passed on empty-handed so
/// the import reports them instead of reading them into memory.
Future<List<LookImportFile>> readLookXFiles(List<XFile> items) async {
  final out = <LookImportFile>[];
  for (final f in await expandFolders(items, extensions: kLookFileExtensions)) {
    final kind = lookFileKind(f.name);
    if (kind == null) continue;
    final cap = kLookFileMaxBytes[kind]!;
    if (await f.length() > cap) {
      out.add(LookImportFile(f.name, Uint8List(cap + 1)));
      continue;
    }
    out.add(LookImportFile(f.name, await f.readAsBytes()));
  }
  return out;
}

/// True when the LUT with [hash] is in this library (an edit opened on
/// another machine may reference one that is not).
final lutAvailableProvider = FutureProvider.family<bool, String>(
  (ref, hash) async => await CreativeLuts.resolve(hash) != null,
);

/// The result of an import plus what it saved.
class LookImportOutcome {
  const LookImportOutcome(
    this.result, {
    required this.saved,
    this.duplicates = 0,
  });

  final LookImportResult result;

  /// Presets and LUT looks added to the library.
  final List<Preset> saved;

  /// Presets left out because the same look is already in the library.
  final int duplicates;

  String get headline {
    final h = result.headline;
    if (duplicates == 0) return h;
    final dup = '$duplicates already in your looks';
    return saved.isEmpty && result.failures.isEmpty ? dup : '$h · $dup';
  }
}

String _newLookId() => 'import.${const Uuid().v4()}';

// Top level, so the isolate closure captures only the files.
Future<LookImportResult> _parseInBackground(List<LookImportFile> files) =>
    runInBackground(
      () => importLookFiles(files, inflate: inflateCapped, newId: _newLookId),
    );

/// What a preset changes, without its identity (duplicate detection).
String _content(Preset p) {
  final j = Map<String, Object?>.of(p.toJson())
    ..remove('id')
    ..remove('createdAt')
    ..remove('import');
  return jsonEncode(j);
}

/// Parses [files] off the UI thread, stores their LUTs in the LUT library
/// and their presets with the user's presets (skipping exact duplicates).
Future<LookImportOutcome> importLooksInto(
  WidgetRef ref,
  List<LookImportFile> files,
) async {
  final result = await _parseInBackground(files);
  final luts = ref.read(lutRepositoryProvider);
  for (final lut in result.luts) {
    await luts.save(lut);
    CreativeLuts.remember(lut);
  }
  final existing = {
    for (final p in await ref.read(userPresetsProvider.future)) _content(p),
  };
  final saved = <Preset>[];
  for (final p in result.presets) {
    if (existing.add(_content(p))) saved.add(p);
  }
  await ref.read(userPresetsProvider.notifier).saveAll(saved);
  if (result.luts.isNotEmpty) ref.invalidate(lutAvailableProvider);
  return LookImportOutcome(
    result,
    saved: List.unmodifiable(saved),
    duplicates: result.presets.length - saved.length,
  );
}
