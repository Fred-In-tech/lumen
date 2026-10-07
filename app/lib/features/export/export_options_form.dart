import 'package:flutter/material.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen/widgets/segmented.dart';

/// Size choices of the form; a box limit (Instagram) shows as its own
/// option while it is selected.
enum _SizeMode { full, longEdge, megapixels, box }

_SizeMode _modeOf(ExportSizeLimit s) => s.isNone
    ? _SizeMode.full
    : s.longEdgePixels != null
    ? _SizeMode.longEdge
    : s.megapixelLimit != null
    ? _SizeMode.megapixels
    : _SizeMode.box;

/// The editable settings of one export preset (format, quality, size,
/// output sharpening, file naming, watermark, metadata). Every change
/// calls [onChanged] with the new settings.
class ExportOptionsForm extends StatefulWidget {
  const ExportOptionsForm({
    super.key,
    required this.preset,
    required this.onChanged,
    required this.narrow,
    this.depthHint,
    this.namePreview,
  });

  final ExportPreset preset;
  final ValueChanged<ExportPreset> onChanged;
  final bool narrow;

  /// Shown under the format when a 16-bit format is chosen.
  final String? depthHint;

  /// The first file's name with the current template.
  final String? namePreview;

  @override
  State<ExportOptionsForm> createState() => _ExportOptionsFormState();
}

class _ExportOptionsFormState extends State<ExportOptionsForm> {
  final _naming = TextEditingController();
  final _sizeValue = TextEditingController();
  final _markText = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ExportOptionsForm old) {
    super.didUpdateWidget(old);
    if (old.preset.id != widget.preset.id) _sync();
  }

  void _sync() {
    final p = widget.preset;
    _naming.text = p.naming;
    _sizeValue.text =
        (p.size.longEdgePixels ?? p.size.megapixelLimit)?.toString() ?? '';
    _markText.text = p.watermark?.text ?? '';
  }

  @override
  void dispose() {
    _naming.dispose();
    _sizeValue.dispose();
    _markText.dispose();
    super.dispose();
  }

  void _set(ExportPreset p) => widget.onChanged(p);

  ExportSizeLimit _limit(_SizeMode mode, String text) {
    final v = int.tryParse(text.trim());
    return switch (mode) {
      _SizeMode.full || _SizeMode.box => const ExportSizeLimit.none(),
      _SizeMode.longEdge =>
        v == null || v < 16
            ? const ExportSizeLimit.longEdge(2048)
            : ExportSizeLimit.longEdge(v.clamp(16, 16384)),
      _SizeMode.megapixels =>
        v == null || v < 1
            ? const ExportSizeLimit.megapixels(12)
            : ExportSizeLimit.megapixels(v.clamp(1, 200)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = widget.preset;
    final narrow = widget.narrow;
    final sliderWidth = narrow ? MediaQuery.sizeOf(context).width - 140 : 360.0;
    InputDecoration deco(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: t.surface1,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Rad.sm),
        borderSide: BorderSide(color: t.lineStrong),
      ),
    );
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.s3),
      child: Text(
        text,
        style: LumenType.caption().copyWith(color: t.textTertiary),
      ),
    );
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
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: child,
                  ),
                ),
              ],
            ),
    );
    final mode = _modeOf(p.size);
    final mark = p.watermark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          'Format',
          Segmented<ExportFileFormat>(
            value: p.format,
            options: {for (final f in ExportFileFormat.values) f: f.label},
            onChanged: (v) => _set(p.copyWith(format: v)),
          ),
        ),
        if (p.format.sixteenBit && widget.depthHint != null)
          caption(widget.depthHint!),
        if (p.format.hasQuality)
          row(
            'Quality',
            SizedBox(
              width: sliderWidth,
              child: LumenSlider(
                label: 'JPEG quality',
                value: p.quality.toDouble(),
                min: 1,
                max: 100,
                defaultValue: 90,
                bipolar: false,
                onChanged: (v) => _set(p.copyWith(quality: v.round())),
                onCommit: (v) => _set(p.copyWith(quality: v.round())),
              ),
            ),
          ),
        row(
          'Size',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Segmented<_SizeMode>(
                value: mode,
                options: {
                  _SizeMode.full: 'Full size',
                  _SizeMode.longEdge: 'Long edge',
                  _SizeMode.megapixels: 'Megapixels',
                  if (mode == _SizeMode.box) _SizeMode.box: p.size.label,
                },
                onChanged: (m) {
                  if (m == _SizeMode.box) return;
                  final limit = _limit(m, _sizeValue.text);
                  _sizeValue.text =
                      (limit.longEdgePixels ?? limit.megapixelLimit)
                          ?.toString() ??
                      '';
                  _set(p.copyWith(size: limit));
                },
              ),
              if (mode == _SizeMode.longEdge ||
                  mode == _SizeMode.megapixels) ...[
                const SizedBox(width: Sp.s2),
                SizedBox(
                  width: 72,
                  child: TextField(
                    key: const ValueKey('export-size-value'),
                    controller: _sizeValue,
                    keyboardType: TextInputType.number,
                    style: LumenType.body().copyWith(color: t.textPrimary),
                    decoration: deco(mode == _SizeMode.longEdge ? 'px' : 'MP'),
                    onChanged: (v) => _set(p.copyWith(size: _limit(mode, v))),
                  ),
                ),
                const SizedBox(width: Sp.s1),
                Text(
                  mode == _SizeMode.longEdge ? 'px' : 'MP',
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
              ],
            ],
          ),
        ),
        row(
          'Sharpen',
          Segmented<OutputSharpen>(
            value: p.sharpen,
            options: {for (final s in OutputSharpen.values) s: s.label},
            onChanged: (v) => _set(p.copyWith(sharpen: v)),
          ),
        ),
        row(
          'File name',
          SizedBox(
            width: narrow ? MediaQuery.sizeOf(context).width - 120 : 320,
            child: TextField(
              key: const ValueKey('export-naming'),
              controller: _naming,
              style: LumenType.body().copyWith(color: t.textPrimary),
              decoration: deco(kDefaultNaming),
              onChanged: (v) => _set(
                p.copyWith(naming: v.trim().isEmpty ? kDefaultNaming : v),
              ),
            ),
          ),
        ),
        caption(
          'Tokens: {name} {date} {seq} {preset}'
          '${widget.namePreview == null ? '' : '  ·  ${widget.namePreview}'}',
        ),
        row(
          'Watermark',
          Segmented<bool>(
            value: mark != null,
            options: const {false: 'Off', true: 'Text'},
            onChanged: (on) {
              if (!on) return _set(p.copyWith(clearWatermark: true));
              final text = _markText.text.trim().isEmpty
                  ? '©'
                  : _markText.text.trim();
              _markText.text = text;
              _set(p.copyWith(watermark: Watermark(text: text)));
            },
          ),
        ),
        if (mark != null) ...[
          row(
            'Text',
            SizedBox(
              width: narrow ? MediaQuery.sizeOf(context).width - 120 : 320,
              child: TextField(
                key: const ValueKey('export-watermark-text'),
                controller: _markText,
                style: LumenType.body().copyWith(color: t.textPrimary),
                decoration: deco('© Your name'),
                onChanged: (v) => _set(
                  p.copyWith(
                    watermark: Watermark(
                      text: v.trim().isEmpty ? '©' : v,
                      position: mark.position,
                      opacity: mark.opacity,
                      size: mark.size,
                    ),
                  ),
                ),
              ),
            ),
          ),
          row(
            'Position',
            Segmented<WatermarkPosition>(
              value: mark.position,
              options: {for (final w in WatermarkPosition.values) w: w.label},
              onChanged: (v) => _set(
                p.copyWith(
                  watermark: Watermark(
                    text: mark.text,
                    position: v,
                    opacity: mark.opacity,
                    size: mark.size,
                  ),
                ),
              ),
            ),
          ),
          row(
            'Opacity',
            SizedBox(
              width: sliderWidth,
              child: LumenSlider(
                label: 'Watermark opacity',
                value: mark.opacity * 100,
                min: 5,
                max: 100,
                defaultValue: 60,
                bipolar: false,
                onChanged: (v) => _set(_markWith(p, mark, opacity: v / 100)),
                onCommit: (v) => _set(_markWith(p, mark, opacity: v / 100)),
              ),
            ),
          ),
          row(
            'Text size',
            SizedBox(
              width: sliderWidth,
              child: LumenSlider(
                label: 'Watermark size (% of the short edge)',
                value: mark.size * 100,
                min: kWatermarkMinSize * 100,
                max: kWatermarkMaxSize * 100,
                defaultValue: 4,
                bipolar: false,
                onChanged: (v) => _set(_markWith(p, mark, size: v / 100)),
                onCommit: (v) => _set(_markWith(p, mark, size: v / 100)),
              ),
            ),
          ),
        ],
        row(
          'Metadata',
          Segmented<bool>(
            value: p.keepMetadata,
            options: const {true: 'Keep (no location)', false: 'Remove all'},
            onChanged: (v) => _set(p.copyWith(keepMetadata: v)),
          ),
        ),
        caption('Location data and serial numbers are always removed.'),
      ],
    );
  }
}

ExportPreset _markWith(
  ExportPreset p,
  Watermark m, {
  double? opacity,
  double? size,
}) => p.copyWith(
  watermark: Watermark(
    text: m.text,
    position: m.position,
    opacity: opacity ?? m.opacity,
    size: size ?? m.size,
  ),
);
