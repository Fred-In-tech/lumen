import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_auto_run.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/module_overlay.dart';
import 'package:lumen/features/search/control_index.dart';
import 'package:lumen/features/search/open_control.dart';

/// Opens the control search (`/` or the search button) for [assetId].
Future<void> showControlSearch(
  BuildContext context,
  WidgetRef ref,
  String assetId, {
  EditorSession? session,
}) async {
  final picked = await showDialog<ControlEntry>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (_) => const _ControlSearchDialog(),
  );
  if (picked == null || !context.mounted) return;
  openControl(
    ref.read,
    assetId,
    picked,
    sourceSize: session == null ? const Size(1, 1) : sourceSizeOf(session),
    runAuto: session == null ? null : () => unawaited(runAiAuto(ref, session)),
  );
}

class _ControlSearchDialog extends StatefulWidget {
  const _ControlSearchDialog();

  @override
  State<_ControlSearchDialog> createState() => _ControlSearchDialogState();
}

class _ControlSearchDialogState extends State<_ControlSearchDialog> {
  final _index = buildControlIndex();
  final _query = TextEditingController();
  List<ControlEntry> _results = const [];
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search(String q) => setState(() {
    _results = searchControls(_index, q);
    _selected = 0;
  });

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
      setState(() => _selected = (_selected + 1) % _results.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && _results.isNotEmpty) {
      setState(
        () => _selected = (_selected - 1 + _results.length) % _results.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _pick(int i) {
    if (i >= 0 && i < _results.length) Navigator.of(context).pop(_results[i]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Dialog(
      backgroundColor: t.surface2,
      alignment: const Alignment(0, -0.5),
      insetPadding: const EdgeInsets.all(Sp.s4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 440),
        child: Focus(
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(Sp.s3),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  onChanged: _search,
                  onSubmitted: (_) => _pick(_selected),
                  style: LumenType.body().copyWith(color: t.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search controls: “teeth”, “pimple”, “warmer”…',
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 16,
                      color: t.textTertiary,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              if (_query.text.isNotEmpty && _results.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.s4, 0, Sp.s4, Sp.s4),
                  child: Text(
                    'No control matches “${_query.text}”.',
                    style: LumenType.body().copyWith(color: t.textTertiary),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Sp.s2),
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final e = _results[i];
                    final selected = i == _selected;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: '${e.title}, ${e.path}',
                      child: InkWell(
                        onTap: () => _pick(i),
                        child: Container(
                          color: selected ? t.surface3 : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Sp.s4,
                            vertical: Sp.s2,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                e.module.icon,
                                size: 16,
                                color: t.textSecondary,
                              ),
                              const SizedBox(width: Sp.s3),
                              Expanded(
                                child: Text(
                                  e.title,
                                  style: LumenType.body().copyWith(
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                e.path,
                                style: LumenType.caption().copyWith(
                                  color: t.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
