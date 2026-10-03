import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:uuid/uuid.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Built-in + user presets with apply-on-click and "save current" (DESIGN.md §3.3).
class PresetsPanel extends ConsumerWidget {
  const PresetsPanel({super.key, required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final user = ref.watch(userPresetsProvider).value ?? const <Preset>[];
    final ctl = ref.read(editorProvider(assetId).notifier);
    Widget row(Preset p) => _PresetRow(
          preset: p,
          onApply: () => ctl.applyPreset(p),
          onDelete: p.builtIn ? null : () => ref.read(userPresetsProvider.notifier).remove(p.id),
        );
    final groups = <String, List<Preset>>{};
    for (final p in kBuiltinPresets) {
      groups.putIfAbsent(p.group, () => []).add(p);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LumenButton(
        label: 'Save current as preset',
        icon: const Icon(LucideIcons.plus),
        onPressed: () => _savePreset(context, ref),
        expand: true,
      ),
      const SizedBox(height: Sp.s4),
      if (user.isNotEmpty) ...[
        Text('Yours', style: LumenType.caption().copyWith(color: t.textTertiary)),
        const SizedBox(height: Sp.s1),
        for (final p in user) row(p),
        const SizedBox(height: Sp.s3),
      ],
      for (final g in groups.entries) ...[
        Text(g.key, style: LumenType.caption().copyWith(color: t.textTertiary)),
        const SizedBox(height: Sp.s1),
        for (final p in g.value) row(p),
        const SizedBox(height: Sp.s3),
      ],
    ]);
  }

  Future<void> _savePreset(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(editorProvider(assetId)).value?.settings;
    if (settings == null) return;
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || name.trim().isEmpty) return;
    final preset = Preset.fromSettings(id: 'user.${const Uuid().v4()}', name: name.trim(), settings: settings);
    await ref.read(userPresetsProvider.notifier).save(preset);
    if (context.mounted) showToast(context, 'Preset “${preset.name}” saved.', kind: ToastKind.success);
  }
}

class _PresetRow extends StatefulWidget {
  const _PresetRow({required this.preset, required this.onApply, this.onDelete});
  final Preset preset;
  final VoidCallback onApply;
  final VoidCallback? onDelete;

  @override
  State<_PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<_PresetRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Apply preset ${widget.preset.name}',
        child: GestureDetector(
          onTap: widget.onApply,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: Sp.s2),
            decoration: BoxDecoration(color: _hover ? t.hoverOverlay : Colors.transparent, borderRadius: BorderRadius.circular(Rad.sm)),
            child: Row(children: [
              Icon(LucideIcons.swatchBook, size: 14, color: t.textTertiary),
              const SizedBox(width: Sp.s2),
              Expanded(child: Text(widget.preset.name, style: LumenType.bodyStrong().copyWith(color: t.textPrimary))),
              if (widget.onDelete != null && _hover)
                GestureDetector(onTap: widget.onDelete, child: Icon(LucideIcons.trash2, size: 14, color: t.textTertiary)),
            ]),
          ),
        ),
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
      title: Text('Save preset', style: LumenType.title().copyWith(color: t.textPrimary)),
      content: TextField(
        controller: _c,
        autofocus: true,
        style: LumenType.body().copyWith(color: t.textPrimary),
        decoration: const InputDecoration(hintText: 'Preset name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        LumenButton(label: 'Cancel', kind: ButtonKind.ghost, onPressed: () => Navigator.pop(context)),
        LumenButton(label: 'Save', kind: ButtonKind.primary, onPressed: () => Navigator.pop(context, _c.text)),
      ],
    );
  }
}
