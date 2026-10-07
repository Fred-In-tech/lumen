/// Turns dropped or picked files into looks: Lightroom presets (`.xmp`,
/// `.lrtemplate`), `.cube` LUTs and `.zip` bundles of either.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../model/creative_lut.dart';
import '../model/preset.dart';
import 'cube_lut.dart';
import 'lightroom_mapping.dart';
import 'lrtemplate_preset.dart';
import 'xmp_preset.dart';
import 'zip_reader.dart';

enum LookFileKind { xmp, lrtemplate, cube, zip }

/// The kind of a look file by its extension, or null.
LookFileKind? lookFileKind(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'xmp' => LookFileKind.xmp,
    'lrtemplate' => LookFileKind.lrtemplate,
    'cube' => LookFileKind.cube,
    'zip' => LookFileKind.zip,
    _ => null,
  };
}

/// Extensions the import accepts (file pickers).
const List<String> kLookFileExtensions = ['xmp', 'lrtemplate', 'zip', 'cube'];

bool isLookFile(String name) => lookFileKind(name) != null;

/// A file handed to the import: its name (or path inside a zip) and bytes.
class LookImportFile {
  const LookImportFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// A file (or zip entry) that could not be imported, and why.
class LookImportFailure {
  const LookImportFailure(this.fileName, this.reason);
  final String fileName;
  final String reason;
}

/// Everything one import produced.
class LookImportResult {
  const LookImportResult({
    required this.presets,
    required this.luts,
    required this.failures,
  });

  /// Converted presets and LUT looks (`Preset.isLutOnly`), ready to save.
  final List<Preset> presets;

  /// LUT data the presets reference, one per content hash.
  final List<CubeLut> luts;
  final List<LookImportFailure> failures;

  int get presetCount =>
      presets.where((p) => p.source == PresetSource.lightroom).length;
  int get lutCount => presets.where((p) => p.source == PresetSource.lut).length;

  /// "12 presets imported · 2 LUTs · 1 file skipped".
  String get headline {
    final parts = <String>[
      if (presetCount > 0)
        '$presetCount ${presetCount == 1 ? 'preset' : 'presets'} imported',
      if (lutCount > 0) '$lutCount ${lutCount == 1 ? 'LUT' : 'LUTs'} imported',
      if (failures.isNotEmpty)
        '${failures.length} ${failures.length == 1 ? 'file' : 'files'} '
            'not imported',
    ];
    return parts.isEmpty ? 'Nothing to import' : parts.join(' · ');
  }
}

/// One line per preset with settings Lumen could not apply:
/// `3 settings in "Moody Film" have no Lumen equivalent: Calibration, …`.
String? skippedLine(Preset p) {
  final s = p.importReport?.skipped ?? const <String>[];
  if (s.isEmpty) return null;
  final n = s.length;
  return '$n ${n == 1 ? 'setting' : 'settings'} in “${p.name}” '
      '${n == 1 ? 'has' : 'have'} no equivalent here: ${s.join(', ')}';
}

/// Size caps per file kind (bytes).
const Map<LookFileKind, int> kLookFileMaxBytes = {
  LookFileKind.xmp: 8 * 1024 * 1024,
  LookFileKind.lrtemplate: 4 * 1024 * 1024,
  LookFileKind.cube: CubeLut.maxFileBytes,
  LookFileKind.zip: 128 * 1024 * 1024,
};

/// Imports [files]. Never throws for bad input: every rejected file is a
/// [LookImportFailure]. [newId] makes preset ids; [inflate] unpacks zips.
LookImportResult importLookFiles(
  List<LookImportFile> files, {
  required Inflate inflate,
  required String Function() newId,
  DateTime? now,
}) {
  final b = _Builder(newId, now ?? DateTime.now().toUtc());
  for (final f in files) {
    final kind = lookFileKind(f.name);
    if (kind == null) {
      b.fail(f.name, 'Not a preset or LUT file.');
    } else if (f.bytes.length > kLookFileMaxBytes[kind]!) {
      b.fail(f.name, 'The file is too large.');
    } else if (kind == LookFileKind.zip) {
      _zip(f, inflate, b);
    } else {
      b.single(f.name, f.bytes, kind, group: null);
    }
  }
  return LookImportResult(
    presets: List.unmodifiable(b.presets),
    luts: List.unmodifiable(b.luts.values),
    failures: List.unmodifiable(b.failures),
  );
}

void _zip(LookImportFile f, Inflate inflate, _Builder b) {
  final List<ZipEntry> entries;
  try {
    entries = readZip(
      f.bytes,
      inflate: inflate,
      want: (p) {
        final k = lookFileKind(p);
        return k != null && k != LookFileKind.zip;
      },
    );
  } on ZipFormatException catch (e) {
    b.fail(f.name, e.message);
    return;
  }
  if (entries.isEmpty) {
    b.fail(f.name, 'The archive holds no presets or LUTs.');
    return;
  }
  final zipName = _baseName(f.name);
  final dirs = [for (final e in entries) _dirs(e.path)];
  // A single folder around everything is the bundle itself, not a group.
  final common =
      dirs.every((d) => d.isNotEmpty && d.first == dirs.first.first) &&
          dirs.any((d) => d.length > 1)
      ? 1
      : 0;
  for (var k = 0; k < entries.length; k++) {
    final e = entries[k];
    final d = dirs[k].skip(common).toList();
    final group = d.isEmpty
        ? (dirs[k].isEmpty ? zipName : dirs[k].last)
        : d.join(' / ');
    final kind = lookFileKind(e.path)!;
    if (e.bytes.length > kLookFileMaxBytes[kind]!) {
      b.fail('${f.name} › ${e.path}', 'The file is too large.');
      continue;
    }
    b.single('${f.name} › ${e.path}', e.bytes, kind, group: group);
  }
}

List<String> _dirs(String path) {
  final parts = path.split('/')..removeLast();
  return [
    for (final p in parts)
      if (p.isNotEmpty && p != '.') p,
  ];
}

String _baseName(String name) {
  final slash = name.replaceAll(r'\', '/').lastIndexOf('/');
  final base = name.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// Text of a preset file: UTF-8 (BOM stripped) or UTF-16 with a BOM.
String decodeLookText(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    final le = bytes[0] == 0xff;
    final units = <int>[
      for (var i = 2; i + 1 < bytes.length; i += 2)
        le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
    ];
    return String.fromCharCodes(units);
  }
  final s = utf8.decode(bytes, allowMalformed: true);
  return s.startsWith('﻿') ? s.substring(1) : s;
}

class _Builder {
  _Builder(this.newId, this.now);

  final String Function() newId;
  final DateTime now;
  final presets = <Preset>[];
  final luts = <String, CubeLut>{};
  final failures = <LookImportFailure>[];

  void fail(String name, String reason) =>
      failures.add(LookImportFailure(name, reason));

  void single(
    String name,
    Uint8List bytes,
    LookFileKind kind, {
    required String? group,
  }) {
    final text = decodeLookText(bytes);
    try {
      switch (kind) {
        case LookFileKind.cube:
          _cube(name, text, group);
        case LookFileKind.xmp:
          _preset(name, readXmpPreset(text), group);
        case LookFileKind.lrtemplate:
          _preset(name, readLrTemplate(text), group);
        case LookFileKind.zip:
          fail(name, 'Archives inside archives are not opened.');
      }
    } on PresetFormatException catch (e) {
      fail(name, e.message);
    } on CubeFormatException catch (e) {
      fail(name, e.message);
    }
  }

  void _cube(String name, String text, String? group) {
    final base = _baseName(name.split(' › ').last);
    final parsed = CubeLut.parse(text, fallbackTitle: base);
    final lut = luts.putIfAbsent(parsed.contentHash, () => parsed);
    final title = parsed.title == base || _genericTitle(parsed.title)
        ? base
        : parsed.title;
    presets.add(
      Preset(
        id: newId(),
        name: title,
        group: group ?? 'LUTs',
        values: const {},
        lut: LutRef(hash: lut.contentHash, name: title),
        source: PresetSource.lut,
        importReport: PresetImportReport(
          fileName: name,
          applied: ['Creative LUT (${lut.size}³)'],
        ),
        createdAt: now,
      ),
    );
  }

  static bool _genericTitle(String t) {
    final l = t.toLowerCase();
    return l.isEmpty ||
        l.startsWith('generated by') ||
        l.startsWith('created with') ||
        l == 'lut';
  }

  void _preset(String name, LightroomPresetData data, String? group) {
    final c = convertLightroomSettings(data.settings);
    if (c.isEmpty) {
      final what = c.skipped.isEmpty ? '' : ' (${c.skipped.join(', ')})';
      fail(name, 'Nothing in this preset has an equivalent here$what.');
      return;
    }
    final title = data.name ?? _baseName(name.split(' › ').last);
    presets.add(
      Preset(
        id: newId(),
        name: title,
        group: group ?? data.group ?? 'Imported',
        values: c.values,
        curves: c.curves,
        curveChannels: c.curveChannels,
        treatment: c.treatment,
        source: PresetSource.lightroom,
        importReport: PresetImportReport(
          fileName: name,
          applied: c.applied,
          approximated: c.approximated,
          skipped: c.skipped,
        ),
        createdAt: now,
      ),
    );
  }
}
