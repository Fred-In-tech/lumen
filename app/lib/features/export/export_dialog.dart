import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/app_settings.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/renderer/gpu_float_export.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/export/backdrop_export.dart';
import 'package:lumen/features/export/export_batch.dart';
import 'package:lumen/features/export/export_options_form.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/export/export_targets.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/import/bit_depth.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Full-res renderer used for export (GPU when installed, CPU reference otherwise).
final fullResRendererProvider = Provider<FullResRenderer>(
  (ref) => gpuFullResRender,
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    ref.watch(catalogRepositoryProvider),
    renderer: ref.watch(fullResRendererProvider),
    patches: () => ref.read(patchStoreProvider.future),
    maskLoader: ref.watch(aiMaskRasterLoaderProvider),
    retouch: ref.watch(storedRetouchLoaderProvider).load,
    backdrop: backdropInputsLoader(
      source: ref.watch(aiMaskSourceProvider),
      loader: ref.watch(aiMaskRasterLoaderProvider),
      patches: () => ref.read(patchStoreProvider.future),
    ),
    sourceRenderer: const GpuSourceRenderer(),
    floatExport: gpuFloatExport(ref.watch(floatSourcesProvider).open),
  ),
);

/// Built-in presets followed by the user's own.
List<ExportPreset> allExportPresets(AppSettings? s) => [
  ...kBuiltinExportPresets,
  ...?s?.exportPresets,
];

/// The settings the dialog opens with: the preset picked last, else the
/// last custom settings (or the pre-preset export preferences).
({ExportPreset preset, String? presetId}) initialExportPreset(AppSettings? s) {
  final id = s?.exportPresetId;
  for (final p in allExportPresets(s)) {
    if (p.id == id) return (preset: p, presetId: id);
  }
  final last = s?.exportLast;
  if (last != null) {
    return (preset: last.copyWith(id: 'custom'), presetId: null);
  }
  return (
    preset: ExportPreset(
      id: 'custom',
      name: 'Custom',
      format: ExportFileFormat.byName(s?.exportFormat),
      quality: s?.exportQuality ?? 90,
      size: s?.exportLongEdge == null
          ? const ExportSizeLimit.none()
          : ExportSizeLimit.longEdge(s!.exportLongEdge!),
      keepMetadata: s?.exportKeepMetadata ?? true,
    ),
    presetId: null,
  );
}

/// The 16-bit note for [entries]: 8-bit photos gain no detail.
String depthHintFor(List<CatalogEntry> entries) {
  final eight = entries
      .where((e) => !isHighBitDepth(e.format, e.bitDepth))
      .length;
  if (entries.length == 1) {
    return eight == 1
        ? 'This photo is 8-bit; 16-bit adds no detail.'
        : 'High-bit-depth source: the file keeps the precision the editor '
              'works in.';
  }
  if (eight == 0) return 'All photos have high-bit-depth sources.';
  return '$eight of ${entries.length} photos are 8-bit; 16-bit adds no '
      'detail to those.';
}

/// Opens the export dialog for [assetIds] (DESIGN.md §3.7): one photo
/// from the editor, many from the library selection (batch).
Future<void> showExportDialog(
  BuildContext context,
  WidgetRef ref,
  List<String> assetIds,
) async {
  if (assetIds.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(assetIds: assetIds),
  );
}

class _ExportDialog extends ConsumerStatefulWidget {
  const _ExportDialog({required this.assetIds});
  final List<String> assetIds;

  @override
  ConsumerState<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<_ExportDialog> {
  late ExportPreset _p;
  String? _presetId;
  List<CatalogEntry> _entries = const [];
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  String? _current;
  ExportBatchResult? _result;

  @override
  void initState() {
    super.initState();
    final init = initialExportPreset(ref.read(settingsProvider).value);
    _p = init.preset;
    _presetId = init.presetId;
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final catalog = ref.read(catalogRepositoryProvider);
    final out = <CatalogEntry>[];
    for (final id in widget.assetIds) {
      final e = await catalog.get(id);
      if (e != null) out.add(e);
    }
    if (mounted) setState(() => _entries = out);
  }

  void _edit(ExportPreset p) => setState(() {
    _p = p.copyWith(id: 'custom', builtin: false);
    _presetId = null;
  });

  void _pick(String? id) {
    if (id == null) return;
    final s = ref.read(settingsProvider).value;
    for (final p in allExportPresets(s)) {
      if (p.id == id) {
        setState(() {
          _p = p;
          _presetId = id;
        });
      }
    }
  }

  Future<void> _saveAsPreset() async {
    final name = await _askName(context, _presetId == null ? '' : _p.name);
    if (name == null || name.trim().isEmpty) return;
    final s = ref.read(settingsProvider).value;
    final existing = s?.exportPresets.where((p) => p.name == name.trim());
    final id = existing == null || existing.isEmpty
        ? 'user-${DateTime.now().microsecondsSinceEpoch}'
        : existing.first.id;
    final preset = _p.copyWith(id: id, name: name.trim(), builtin: false);
    await ref
        .read(settingsProvider.notifier)
        .change(
          (s) => s.copyWith(
            exportPresets: [
              for (final p in s.exportPresets)
                if (p.id != id) p,
              preset,
            ],
            exportPresetId: id,
          ),
        );
    if (!mounted) return;
    setState(() {
      _p = preset;
      _presetId = id;
    });
    showToast(context, 'Preset "${preset.name}" saved.');
  }

  Future<void> _deletePreset() async {
    final id = _presetId;
    if (id == null || _p.builtin) return;
    await ref
        .read(settingsProvider.notifier)
        .change(
          (s) => s.copyWith(
            exportPresets: [
              for (final p in s.exportPresets)
                if (p.id != id) p,
            ],
            clearExportPresetId: true,
          ),
        );
    if (!mounted) return;
    setState(() {
      _p = _p.copyWith(id: 'custom', name: 'Custom');
      _presetId = null;
    });
  }

  Future<void> _chooseFolder() async {
    final folder = await chooseExportFolder(initial: _p.folder);
    if (folder != null) _edit(_p.copyWith(folder: folder));
  }

  Future<void> _run() async {
    final mobile = ref.read(platformInfoProvider).isMobile;
    String? folder;
    if (kExportNeedsFolder && !mobile) {
      folder = await chooseExportFolder(initial: _p.folder);
      if (folder == null) return;
    } else if (kExportNeedsFolder) {
      folder = await shareStagingFolder();
    }
    await ref
        .read(settingsProvider.notifier)
        .change(
          (s) => s.copyWith(
            exportPresetId: _presetId,
            clearExportPresetId: _presetId == null,
            exportLast: _p,
          ),
        );
    setState(() {
      _running = true;
      _done = 0;
      _current = null;
    });
    final toShare = <ExportedFile>[];
    final batch = ExportBatch(ref.read(exportServiceProvider), (f) async {
      if (folder == null) {
        toShare.add(f);
        return null;
      }
      return (await writeExports(folder, [f])).first;
    }, catalog: ref.read(catalogRepositoryProvider));
    final result = await batch.run(
      widget.assetIds,
      ExportOptions.fromPreset(_p),
      isCancelled: () => _cancel,
      onProgress: (done, _, current) {
        if (mounted) {
          setState(() {
            _done = done;
            _current = current;
          });
        }
      },
    );
    if (mobile && result.written.isNotEmpty) {
      await sharePaths(result.written);
    } else if (folder == null && toShare.isNotEmpty) {
      await shareExports(toShare);
    }
    if (!mounted) return;
    if (result.failures.isNotEmpty) {
      setState(() {
        _running = false;
        _result = result;
      });
      return;
    }
    Navigator.of(context).pop();
    showToast(context, exportSummary(result, mobile ? null : folder));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.assetIds.length;
    final title = n == 1 ? 'Export photo' : 'Export $n photos';
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final result = _result;
    return Dialog(
      backgroundColor: t.surface2,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sp.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: LumenType.title().copyWith(color: t.textPrimary),
              ),
              const SizedBox(height: Sp.s5),
              if (result != null)
                ..._resultView(t, result)
              else if (_running)
                ..._progressView(t, n)
              else
                ..._settingsView(t, n, narrow),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _progressView(LumenTokens t, int n) => [
    Text(
      'Exporting ${_done < n ? _done + 1 : n} of $n'
      '${_current == null ? '' : '  ·  $_current'}',
      style: LumenType.body().copyWith(color: t.textSecondary),
    ),
    const SizedBox(height: Sp.s2),
    LinearProgressIndicator(value: n == 0 ? null : _done / n, minHeight: 4),
    const SizedBox(height: Sp.s5),
    Align(
      alignment: Alignment.centerRight,
      child: LumenButton(
        label: _cancel ? 'Stopping after this photo' : 'Cancel',
        onPressed: _cancel ? null : () => setState(() => _cancel = true),
      ),
    ),
  ];

  List<Widget> _resultView(LumenTokens t, ExportBatchResult r) => [
    Text(
      '${r.written.length} of ${r.total} exported. '
      '${r.failures.length} failed:',
      style: LumenType.body().copyWith(color: t.textPrimary),
    ),
    const SizedBox(height: Sp.s3),
    for (final f in r.failures)
      Padding(
        padding: const EdgeInsets.only(bottom: Sp.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.circleAlert, size: 14, color: t.danger),
            const SizedBox(width: Sp.s2),
            Expanded(
              child: Text(
                '${f.name}: ${f.reason}',
                style: LumenType.caption().copyWith(color: t.textSecondary),
              ),
            ),
          ],
        ),
      ),
    const SizedBox(height: Sp.s4),
    Align(
      alignment: Alignment.centerRight,
      child: LumenButton(
        label: 'Close',
        kind: ButtonKind.primary,
        onPressed: () => Navigator.pop(context),
      ),
    ),
  ];

  List<Widget> _settingsView(LumenTokens t, int n, bool narrow) {
    final settings = ref.watch(settingsProvider).value;
    final presets = allExportPresets(settings);
    final first = _entries.isEmpty ? null : _entries.first;
    final preview = first == null
        ? null
        : exportFileNameFor(
            _p.naming,
            original: first.fileName,
            format: _p.format,
            date: first.exif.capturedAt ?? DateTime.now(),
            seq: 1,
            total: n,
            preset: _p.name,
          );
    final userPreset = _presetId != null && !_p.builtin;
    return [
      Row(
        children: [
          SizedBox(
            width: narrow ? null : 96,
            child: Text(
              'Preset',
              style: LumenType.label().copyWith(color: t.textSecondary),
            ),
          ),
          if (narrow) const SizedBox(width: Sp.s2),
          Expanded(
            child: DropdownButton<String>(
              key: const ValueKey('export-preset'),
              value: _presetId ?? 'custom',
              isExpanded: true,
              dropdownColor: t.surface3,
              underline: const SizedBox.shrink(),
              items: [
                for (final p in presets)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      p.name,
                      overflow: TextOverflow.ellipsis,
                      style: LumenType.body().copyWith(color: t.textPrimary),
                    ),
                  ),
                if (_presetId == null)
                  DropdownMenuItem(
                    value: 'custom',
                    child: Text(
                      'Custom',
                      style: LumenType.body().copyWith(color: t.textPrimary),
                    ),
                  ),
              ],
              onChanged: _pick,
            ),
          ),
          LumenIconButton(
            icon: LucideIcons.bookmarkPlus,
            tooltip: 'Save as preset',
            onPressed: _saveAsPreset,
          ),
          if (userPreset)
            LumenIconButton(
              icon: LucideIcons.trash2,
              tooltip: 'Delete preset',
              onPressed: _deletePreset,
            ),
        ],
      ),
      const SizedBox(height: Sp.s3),
      ExportOptionsForm(
        preset: _p,
        onChanged: _edit,
        narrow: narrow,
        depthHint: _entries.isEmpty ? null : depthHintFor(_entries),
        namePreview: preview,
      ),
      if (kExportNeedsFolder && !ref.read(platformInfoProvider).isMobile)
        Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                'Folder',
                style: LumenType.label().copyWith(color: t.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                _p.folder ?? 'Ask when exporting',
                overflow: TextOverflow.ellipsis,
                style: LumenType.body().copyWith(color: t.textPrimary),
              ),
            ),
            LumenIconButton(
              icon: LucideIcons.folderOpen,
              tooltip: 'Default folder',
              onPressed: _chooseFolder,
            ),
            if (_p.folder != null)
              LumenIconButton(
                icon: LucideIcons.x,
                tooltip: 'Ask each time',
                onPressed: () => _edit(_p.copyWith(clearFolder: true)),
              ),
          ],
        ),
      const SizedBox(height: Sp.s5),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          LumenButton(
            label: 'Cancel',
            kind: ButtonKind.ghost,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: Sp.s2),
          LumenButton(
            label: n == 1 ? 'Export' : 'Export $n',
            kind: ButtonKind.primary,
            onPressed: _run,
          ),
        ],
      ),
    ];
  }
}

/// The toast after a batch without failures.
String exportSummary(ExportBatchResult r, String? folder) {
  final n = r.written.length;
  final base = r.cancelled
      ? '$n of ${r.total} exported (cancelled).'
      : '$n ${n == 1 ? 'photo' : 'photos'} exported'
            '${folder != null ? ' to $folder' : ''}.';
  return switch (r.notes.length) {
    0 => base,
    1 => '$base ${r.notes.single}',
    final k =>
      '$base Portrait retouch was skipped on $k photos: face analysis is '
          'unavailable here.',
  };
}

Future<String?> _askName(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PresetNameDialog(initial: initial),
    );

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.initial});
  final String initial;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface2,
      title: Text(
        'Save preset',
        style: LumenType.title().copyWith(color: t.textPrimary),
      ),
      content: TextField(
        key: const ValueKey('export-preset-name'),
        controller: _name,
        autofocus: true,
        style: LumenType.body().copyWith(color: t.textPrimary),
        decoration: const InputDecoration(hintText: 'Preset name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        LumenButton(
          label: 'Cancel',
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        LumenButton(
          label: 'Save',
          kind: ButtonKind.primary,
          onPressed: () => Navigator.pop(context, _name.text),
        ),
      ],
    );
  }
}
