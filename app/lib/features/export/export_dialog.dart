import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/backdrop_export.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/export/export_targets.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen/widgets/segmented.dart';
import 'package:lumen/widgets/toast.dart';

final _log = Logger('Export');

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
  ),
);

/// Opens the export dialog for [assetIds] (DESIGN.md §3.7).
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
  ExportFormat _format = ExportFormat.jpeg;
  double _quality = 90;
  int? _longEdge;
  bool _keepMetadata = true;
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider).value;
    if (s != null) {
      _format = s.exportFormat == 'png' ? ExportFormat.png : ExportFormat.jpeg;
      _quality = s.exportQuality.toDouble();
      _longEdge = s.exportLongEdge;
      _keepMetadata = s.exportKeepMetadata;
    }
  }

  Future<void> _run() async {
    final mobile = ref.read(platformInfoProvider).isMobile;
    String? folder;
    if (kExportNeedsFolder && !mobile) {
      folder = await chooseExportFolder();
      if (folder == null) return;
    }
    await ref
        .read(settingsProvider.notifier)
        .change(
          (s) => s.copyWith(
            exportFormat: _format.name,
            exportQuality: _quality.round(),
            exportLongEdge: _longEdge,
            clearExportLongEdge: _longEdge == null,
            exportKeepMetadata: _keepMetadata,
          ),
        );
    setState(() {
      _running = true;
      _done = 0;
      _error = null;
    });
    final service = ref.read(exportServiceProvider);
    final options = ExportOptions(
      format: _format,
      quality: _quality.round(),
      longEdge: _longEdge,
      keepMetadata: _keepMetadata,
    );
    final files = <ExportedFile>[];
    var failed = 0;
    for (final id in widget.assetIds) {
      if (_cancel) break;
      try {
        final f = await service.exportOne(id, options);
        files.add(f);
        if (folder != null) await writeExports(folder, [f]);
      } on CatalogException catch (e) {
        failed++;
        _log.warning('export $id failed: $e');
      } on Exception catch (e) {
        failed++;
        _log.warning('export $id failed: $e');
      }
      if (mounted) setState(() => _done++);
    }
    if (folder == null && files.isNotEmpty) await shareExports(files);
    if (!mounted) return;
    Navigator.of(context).pop();
    final n = files.length;
    final notes = [for (final f in files) ?f.note];
    final base = failed == 0
        ? '$n ${n == 1 ? 'photo' : 'photos'} exported${folder != null ? ' to $folder' : ''}.'
        : '$n of ${widget.assetIds.length} exported. $failed failed.';
    final msg = switch (notes.length) {
      0 => base,
      1 => '$base ${notes.single}',
      final k =>
        '$base Portrait retouch was skipped on $k photos: face '
            'analysis is unavailable here.',
    };
    showToast(
      context,
      msg,
      kind: failed == 0 ? ToastKind.success : ToastKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.assetIds.length;
    final title = n == 1 ? 'Export photo' : 'Export $n photos';
    final narrow = MediaQuery.sizeOf(context).width < 520;
    // Desktop: label column + control. Phone: label above a horizontally scrollable control.
    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.s3),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: LumenType.label().copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: Sp.s1_5),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: child,
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: LumenType.label().copyWith(color: t.textSecondary),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
    );
    return Dialog(
      backgroundColor: t.surface2,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
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
              if (_running) ...[
                Text(
                  'Exporting $_done of $n',
                  style: LumenType.body().copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: Sp.s2),
                LinearProgressIndicator(
                  value: n == 0 ? null : _done / n,
                  minHeight: 4,
                ),
                const SizedBox(height: Sp.s5),
                Align(
                  alignment: Alignment.centerRight,
                  child: LumenButton(
                    label: 'Cancel',
                    onPressed: () => setState(() => _cancel = true),
                  ),
                ),
              ] else ...[
                row(
                  'Format',
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Segmented<ExportFormat>(
                      value: _format,
                      options: const {
                        ExportFormat.jpeg: 'JPEG',
                        ExportFormat.png: 'PNG',
                      },
                      onChanged: (v) => setState(() => _format = v),
                    ),
                  ),
                ),
                if (_format == ExportFormat.jpeg)
                  row(
                    'Quality',
                    SizedBox(
                      width: narrow
                          ? MediaQuery.sizeOf(context).width - 140
                          : null,
                      child: LumenSlider(
                        label: 'JPEG quality',
                        value: _quality,
                        min: 1,
                        max: 100,
                        defaultValue: 90,
                        bipolar: false,
                        onChanged: (v) => setState(() => _quality = v),
                        onCommit: (v) => setState(() => _quality = v),
                      ),
                    ),
                  ),
                row(
                  'Size',
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Segmented<int?>(
                      value: _longEdge,
                      options: const {
                        null: 'Original',
                        4096: '4096',
                        2048: '2048',
                        1080: '1080',
                      },
                      onChanged: (v) => setState(() => _longEdge = v),
                    ),
                  ),
                ),
                row(
                  'Metadata',
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Segmented<bool>(
                      value: _keepMetadata,
                      options: const {
                        true: 'Keep (no location)',
                        false: 'Remove all',
                      },
                      onChanged: (v) => setState(() => _keepMetadata = v),
                    ),
                  ),
                ),
                Text(
                  'Location data is always removed.',
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: LumenType.body().copyWith(color: t.danger),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
