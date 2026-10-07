import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/thumb_image.dart';

/// The frame every project dialog shares: white card, title, body, buttons.
class ProjectDialogFrame extends StatelessWidget {
  const ProjectDialogFrame({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
    this.maxWidth = 440,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Dialog(
      backgroundColor: t.surface1,
      insetPadding: const EdgeInsets.all(Sp.s4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.xl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
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
              const SizedBox(height: Sp.s3),
              ...children,
              const SizedBox(height: Sp.s6),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Sp.s2,
                runSpacing: Sp.s2,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a project name ([initial] prefilled). Null when cancelled.
Future<String?> showProjectNameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, action: action, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (_c.text.trim().isNotEmpty) Navigator.pop(context, _c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ProjectDialogFrame(
      title: widget.title,
      actions: [
        LumenButton(
          label: 'Cancel',
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        LumenButton(
          label: widget.action,
          kind: ButtonKind.primary,
          onPressed: _c.text.trim().isEmpty ? null : _submit,
        ),
      ],
      children: [
        TextField(
          key: const ValueKey('project-name-field'),
          controller: _c,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          style: LumenType.body().copyWith(color: t.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Project name',
            filled: true,
            fillColor: t.surface1,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Rad.sm),
              borderSide: BorderSide(color: t.lineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Rad.sm),
              borderSide: BorderSide(color: t.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Confirms deleting [summary]'s project. Returns null when cancelled,
/// else whether its photos go too (false: they become Unsorted).
Future<bool?> showDeleteProjectDialog(
  BuildContext context,
  ProjectSummary summary,
) => showDialog<bool>(
  context: context,
  builder: (_) => DeleteProjectDialog(summary: summary),
);

class DeleteProjectDialog extends StatefulWidget {
  const DeleteProjectDialog({super.key, required this.summary});
  final ProjectSummary summary;

  @override
  State<DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<DeleteProjectDialog> {
  bool _deletePhotos = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.summary.count;
    final photos = n == 1 ? '1 photo' : '$n photos';
    return ProjectDialogFrame(
      title: 'Delete “${widget.summary.name}”?',
      actions: [
        LumenButton(
          label: 'Cancel',
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        LumenButton(
          label: _deletePhotos
              ? 'Delete project and $photos'
              : 'Delete project',
          kind: ButtonKind.danger,
          icon: const Icon(LucideIcons.trash2),
          onPressed: () => Navigator.pop(context, _deletePhotos),
        ),
      ],
      children: [
        if (n == 0)
          Text(
            'The project is empty. Nothing else changes.',
            style: LumenType.body().copyWith(color: t.textSecondary),
          )
        else ...[
          _Choice(
            title: 'Keep the $photos',
            body: 'They move to Unsorted with their edits.',
            selected: !_deletePhotos,
            onTap: () => setState(() => _deletePhotos = false),
          ),
          const SizedBox(height: Sp.s2),
          _Choice(
            title: 'Delete the $photos too',
            body:
                'They leave the library with their edits. Original files '
                'elsewhere on your computer are untouched.',
            selected: _deletePhotos,
            danger: true,
            onTap: () => setState(() => _deletePhotos = true),
          ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final String title;
  final String body;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final edge = danger ? t.danger : t.accent;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        semanticLabel: title,
        scaleOnPress: false,
        radius: Rad.md,
        builder: (context, _) => AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(Sp.s3),
          decoration: BoxDecoration(
            color: selected ? edge.withValues(alpha: 0.08) : t.surface1,
            borderRadius: BorderRadius.circular(Rad.md),
            border: Border.all(
              color: selected ? edge : t.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? edge : t.lineStrong,
                      width: selected ? 5 : 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Sp.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: LumenType.bodyStrong().copyWith(
                        color: danger && selected ? t.danger : t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Sp.s0_5),
                    Text(
                      body,
                      style: LumenType.caption().copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks one of [photos] as the project cover. Null when cancelled.
Future<String?> showCoverPicker(
  BuildContext context,
  List<CatalogEntry> photos, {
  String? current,
}) => showDialog<String>(
  context: context,
  builder: (context) {
    final t = context.tokens;
    return ProjectDialogFrame(
      title: 'Choose a cover',
      maxWidth: 560,
      actions: [
        LumenButton(
          label: 'Cancel',
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      children: [
        SizedBox(
          height: 320,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: Sp.s1_5,
              crossAxisSpacing: Sp.s1_5,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final e = photos[i];
              final on = e.assetId == current;
              return Pressable(
                onTap: () => Navigator.pop(context, e.assetId),
                semanticLabel: 'Use ${e.fileName} as cover',
                radius: Rad.sm,
                builder: (context, states) => Container(
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Rad.sm),
                    border: Border.all(
                      color: on
                          ? t.accent
                          : states.contains(WidgetState.hovered)
                          ? t.lineStrong
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Rad.sm),
                    child: ThumbImage(entry: e),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  },
);

/// Picks a project for a look or preset. [count] says how many photos each
/// option would get. Null when cancelled.
Future<String?> showChooseProjectDialog(
  BuildContext context, {
  required String title,
  required List<ProjectSummary> projects,
}) => showDialog<String>(
  context: context,
  builder: (context) {
    final t = context.tokens;
    return ProjectDialogFrame(
      title: title,
      actions: [
        LumenButton(
          label: 'Cancel',
          kind: ButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      children: [
        Text(
          'Applies to the project’s picks, or to every photo that is not '
          'rejected when nothing is picked yet.',
          style: LumenType.body().copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: Sp.s3),
        for (final s in projects)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.s1),
            child: Pressable(
              onTap: () => Navigator.pop(context, s.project!.id),
              semanticLabel: s.name,
              scaleOnPress: false,
              radius: Rad.md,
              builder: (context, states) => Container(
                padding: const EdgeInsets.all(Sp.s2),
                decoration: BoxDecoration(
                  color: states.contains(WidgetState.hovered)
                      ? t.surface2
                      : t.surface1,
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: Border.all(color: t.line),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Rad.sm),
                      child: SizedBox.square(
                        dimension: 40,
                        child: s.cover == null
                            ? ColoredBox(color: t.surface2)
                            : ThumbImage(entry: s.cover!),
                      ),
                    ),
                    const SizedBox(width: Sp.s3),
                    Expanded(
                      child: Text(
                        s.name,
                        overflow: TextOverflow.ellipsis,
                        style: LumenType.bodyStrong().copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${s.deliverable.length} photos',
                      style: LumenType.caption().copyWith(
                        color: t.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  },
);
