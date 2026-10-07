import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/buttons.dart';

/// Where an import goes.
sealed class ImportDestination {
  const ImportDestination();
}

final class NewProjectDestination extends ImportDestination {
  const NewProjectDestination(this.name);
  final String name;
}

final class ExistingProjectDestination extends ImportDestination {
  const ExistingProjectDestination(this.projectId);
  final String projectId;
}

final class UnsortedDestination extends ImportDestination {
  const UnsortedDestination();
}

enum _Choice { create, existing, unsorted }

/// Asks where [count] photos go: a new project named [suggestedName]
/// (editable), one of [projects], or Unsorted. Null when cancelled.
Future<ImportDestination?> showImportDestinationDialog(
  BuildContext context, {
  required int count,
  required String suggestedName,
  required List<Project> projects,
}) => showDialog<ImportDestination>(
  context: context,
  builder: (_) => ImportDestinationDialog(
    count: count,
    suggestedName: suggestedName,
    projects: projects,
  ),
);

class ImportDestinationDialog extends StatefulWidget {
  const ImportDestinationDialog({
    super.key,
    required this.count,
    required this.suggestedName,
    required this.projects,
  });

  final int count;
  final String suggestedName;
  final List<Project> projects;

  @override
  State<ImportDestinationDialog> createState() =>
      _ImportDestinationDialogState();
}

class _ImportDestinationDialogState extends State<ImportDestinationDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestedName,
  );
  _Choice _choice = _Choice.create;
  late String? _projectId = widget.projects.isEmpty
      ? null
      : widget.projects.first.id;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ImportDestination? get _result => switch (_choice) {
    _Choice.create =>
      _name.text.trim().isEmpty ? null : NewProjectDestination(_name.text),
    _Choice.existing =>
      _projectId == null ? null : ExistingProjectDestination(_projectId!),
    _Choice.unsorted => const UnsortedDestination(),
  };

  void _submit() {
    final r = _result;
    if (r != null) Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.count;
    final label = n == 1 ? 'Import 1 photo' : 'Import $n photos';
    return Dialog(
      backgroundColor: t.surface1,
      insetPadding: const EdgeInsets.all(Sp.s4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Where should these go?',
                  style: LumenType.title().copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: Sp.s1),
                Text(
                  '$n ${n == 1 ? 'photo' : 'photos'} ready to import. '
                  'A project keeps one shoot together from cull to export.',
                  style: LumenType.body().copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: Sp.s5),
                _Option(
                  icon: LucideIcons.folderPlus,
                  title: 'New project',
                  selected: _choice == _Choice.create,
                  onTap: () => setState(() => _choice = _Choice.create),
                  child: TextField(
                    key: const ValueKey('new-project-name'),
                    controller: _name,
                    autofocus: true,
                    onTap: () => setState(() => _choice = _Choice.create),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    style: LumenType.body().copyWith(color: t.textPrimary),
                    decoration: _fieldDecoration(t, 'Project name'),
                  ),
                ),
                if (widget.projects.isNotEmpty) ...[
                  const SizedBox(height: Sp.s2),
                  _Option(
                    icon: LucideIcons.folderOpen,
                    title: 'Add to a project',
                    selected: _choice == _Choice.existing,
                    onTap: () => setState(() => _choice = _Choice.existing),
                    child: _ProjectPicker(
                      projects: widget.projects,
                      value: _projectId,
                      onChanged: (id) => setState(() {
                        _projectId = id;
                        _choice = _Choice.existing;
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: Sp.s2),
                _Option(
                  icon: LucideIcons.inbox,
                  title: 'Unsorted',
                  subtitle: 'Keep them out of projects for now',
                  selected: _choice == _Choice.unsorted,
                  onTap: () => setState(() => _choice = _Choice.unsorted),
                ),
                const SizedBox(height: Sp.s6),
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
                      label: label,
                      kind: ButtonKind.primary,
                      icon: const Icon(LucideIcons.imagePlus),
                      onPressed: _result == null ? null : _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(LumenTokens t, String hint) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: LumenType.body().copyWith(color: t.textTertiary),
  filled: true,
  fillColor: t.surface1,
  contentPadding: const EdgeInsets.symmetric(horizontal: Sp.s3, vertical: 10),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Rad.sm),
    borderSide: BorderSide(color: t.lineStrong),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Rad.sm),
    borderSide: BorderSide(color: t.lineStrong),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Rad.sm),
    borderSide: BorderSide(color: t.accent, width: 1.5),
  ),
);

/// A selectable option card: radio dot, icon, title, and an optional
/// control under the title when selected.
class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        semanticLabel: title,
        scaleOnPress: false,
        radius: Rad.md,
        builder: (context, states) => AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(Sp.s3),
          decoration: BoxDecoration(
            color: selected
                ? t.accentTint
                : states.contains(WidgetState.hovered)
                ? t.surface2
                : t.surface1,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(
              color: selected ? t.accent : t.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? t.accent : t.textSecondary,
                  ),
                  const SizedBox(width: Sp.s2),
                  Expanded(
                    child: Text(
                      title,
                      style: LumenType.bodyStrong().copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  _RadioDot(selected: selected),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Sp.s0_5),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Text(
                    subtitle!,
                    style: LumenType.caption().copyWith(color: t.textTertiary),
                  ),
                ),
              ],
              if (child != null) ...[
                const SizedBox(height: Sp.s2),
                Padding(padding: const EdgeInsets.only(left: 26), child: child),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedContainer(
      duration: Motion.fast,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.surface1,
        border: Border.all(
          color: selected ? t.accent : t.lineStrong,
          width: selected ? 5 : 1.5,
        ),
      ),
    );
  }
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.value,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: t.surface1,
      icon: Icon(LucideIcons.chevronDown, size: 16, color: t.textSecondary),
      decoration: _fieldDecoration(t, 'Choose a project'),
      style: LumenType.body().copyWith(color: t.textPrimary),
      items: [
        for (final p in projects)
          DropdownMenuItem(
            value: p.id,
            child: Text(p.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
