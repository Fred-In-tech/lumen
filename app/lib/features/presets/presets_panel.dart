import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:uuid/uuid.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/home/looks.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/looks/look_previews.dart';
import 'package:lumen/features/looks/look_sample.dart';
import 'package:lumen/features/presets/creative_lut_card.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Presets and LUTs, each shown on the photo being edited; apply on click,
/// "Save current as preset", "Import presets & LUTs" and the applied
/// LUT's amount (DESIGN.md §3.3, "Looks & presets").
class PresetsPanel extends ConsumerStatefulWidget {
  const PresetsPanel({super.key, required this.assetId, this.session});
  final String assetId;

  /// The open photo (its analysis proxy is the preview photo); without it
  /// the tiles use the bundled samples.
  final EditorSession? session;

  @override
  ConsumerState<PresetsPanel> createState() => _PresetsPanelState();
}

class _PresetsPanelState extends ConsumerState<PresetsPanel> {
  Future<LookPreviewPhoto?>? _photo;
  int? _photoVersion;

  Future<LookPreviewPhoto?>? _photoFor(EditorSession? s) {
    if (s == null) return null;
    final proxy = s.renderer.analysisProxy;
    if (proxy == null) return null;
    final v = s.sourceVersion.value;
    if (_photo != null && _photoVersion == v) return _photo;
    _photoVersion = v;
    return _photo = LookPreviewPhoto.fromProxy('${s.assetId}@$v', proxy);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    if (s == null) return _build(context, null);
    return ValueListenableBuilder<int>(
      valueListenable: s.sourceVersion,
      builder: (context, _, _) => ValueListenableBuilder<bool>(
        valueListenable: s.ready,
        builder: (context, _, _) => FutureBuilder<LookPreviewPhoto?>(
          future: _photoFor(s),
          builder: (context, snap) => _build(
            context,
            snap.data,
            waiting:
                snap.connectionState != ConnectionState.done &&
                _photoFor(s) != null,
          ),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    LookPreviewPhoto? photo, {
    bool waiting = false,
  }) {
    final t = context.tokens;
    final assetId = widget.assetId;
    final user = ref.watch(userPresetsProvider).value ?? const <Preset>[];
    final lut = ref.watch(
      editorProvider(assetId).select((s) => s.value?.settings.lut),
    );
    final ctl = ref.read(editorProvider(assetId).notifier);
    final groups = <String, List<Preset>>{};
    for (final p in user) {
      final g = p.source == PresetSource.user ? 'Yours' : p.group;
      groups.putIfAbsent(g, () => []).add(p);
    }
    for (final p in kBuiltinPresets) {
      groups.putIfAbsent(p.group, () => []).add(p);
    }
    Widget tiles(List<Preset> ps) => GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: Sp.s2,
      mainAxisSpacing: Sp.s2,
      childAspectRatio: 0.82,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final p in ps)
          _PresetTile(
            preset: p,
            photo: photo,
            waiting: waiting,
            onApply: () => ctl.applyPreset(p),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumenButton(
          label: 'Save current as preset',
          icon: const Icon(LucideIcons.plus),
          onPressed: () => _savePreset(context),
          expand: true,
        ),
        const SizedBox(height: Sp.s2),
        LumenButton(
          label: 'Import presets & LUTs',
          kind: ButtonKind.ghost,
          icon: const Icon(LucideIcons.fileUp),
          onPressed: () => pickAndImportLooks(context, ref),
          expand: true,
        ),
        if (lut != null) ...[
          const SizedBox(height: Sp.s4),
          CreativeLutCard(assetId: assetId, lut: lut),
        ],
        const SizedBox(height: Sp.s4),
        for (final g in groups.entries) ...[
          Text(
            g.key,
            style: LumenType.caption().copyWith(color: t.textTertiary),
          ),
          const SizedBox(height: Sp.s1),
          tiles(g.value),
          const SizedBox(height: Sp.s3),
        ],
      ],
    );
  }

  Future<void> _savePreset(BuildContext context) async {
    final settings = ref.read(editorProvider(widget.assetId)).value?.settings;
    if (settings == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    final preset = Preset.fromSettings(
      id: 'user.${const Uuid().v4()}',
      name: name.trim(),
      settings: settings,
    );
    await ref.read(userPresetsProvider.notifier).save(preset);
    if (context.mounted) {
      showToast(
        context,
        'Preset “${preset.name}” saved.',
        kind: ToastKind.success,
      );
    }
  }
}

/// A preset on the photo: sample, name, type; click applies.
class _PresetTile extends ConsumerStatefulWidget {
  const _PresetTile({
    required this.preset,
    required this.photo,
    required this.waiting,
    required this.onApply,
  });
  final Preset preset;
  final LookPreviewPhoto? photo;
  final bool waiting;
  final VoidCallback onApply;

  @override
  ConsumerState<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends ConsumerState<_PresetTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = PresetLook(widget.preset);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Apply ${look.kind.label.toLowerCase()} ${look.name}',
        child: GestureDetector(
          onTap: widget.onApply,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Rad.tile + 2),
                    border: Border.all(
                      color: _hover ? t.lineStrong : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Rad.tile),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LookSample(
                          look: look,
                          photo: widget.photo,
                          waiting: widget.waiting,
                          compare: false,
                        ),
                        if (look.kind == LookKind.lut)
                          const Positioned(
                            left: 4,
                            top: 4,
                            child: LookKindChip(kind: LookKind.lut),
                          ),
                        if (look.editable && _hover)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: _TileMenu(look: look),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Sp.s1),
              Text(
                look.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LumenType.label().copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileMenu extends ConsumerWidget {
  const _TileMenu({required this.look});
  final PresetLook look;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return GestureDetector(
      onTapDown: (d) => showLookMenu(context, ref, look, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surface1.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: Icon(LucideIcons.ellipsis, size: 12, color: t.textSecondary),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(
        'Save preset',
        style: LumenType.title().copyWith(color: t.textPrimary),
      ),
      content: TextField(
        controller: _c,
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
          onPressed: () => Navigator.pop(context, _c.text),
        ),
      ],
    );
  }
}
