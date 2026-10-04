import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/masks/mask_kinds.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// One mask in the list: kind icon, name (double-click or long-press to
/// rename), overlay eye, invert, duplicate and delete. Hovering a row shows
/// that mask's overlay on the canvas (Lightroom behaviour).
class MaskRow extends ConsumerStatefulWidget {
  const MaskRow({
    super.key,
    required this.assetId,
    required this.mask,
    required this.selected,
    required this.overlayShown,
    this.canDuplicate = true,
    this.touch = false,
  });

  final String assetId;
  final LocalMask mask;
  final bool selected;

  /// True while this mask's tint is on (selected and the overlay is on).
  final bool overlayShown;
  final bool canDuplicate;
  final bool touch;

  @override
  ConsumerState<MaskRow> createState() => _MaskRowState();
}

class _MaskRowState extends ConsumerState<MaskRow> {
  bool _hover = false;
  bool _renaming = false;
  bool _focused = false;

  /// Time of the last tap: a second tap within [kDoubleTapTimeout] renames.
  /// (A double-tap recognizer would hold the gesture arena and delay every
  /// action button in the row by 300 ms.)
  DateTime? _lastTap;
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  LocalMask get _m => widget.mask;
  MaskUiNotifier get _ui => ref.read(maskUiProvider(widget.assetId).notifier);
  MaskCommands get _cmds => MaskCommands.of(ref, widget.assetId);

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startRename() {
    if (!_m.isSupported) return;
    _name.text = _m.name;
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _m.name.length,
    );
    setState(() => _renaming = true);
    _nameFocus.requestFocus();
  }

  void _onTap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last != null && now.difference(last) < kDoubleTapTimeout) {
      _lastTap = null;
      _startRename();
      return;
    }
    _lastTap = now;
    _ui.select(_m.id);
  }

  void _finishRename({required bool commit}) {
    if (!_renaming) return;
    if (commit) _cmds.rename(_m.id, _name.text);
    setState(() => _renaming = false);
  }

  void _setHover(bool v) {
    setState(() => _hover = v);
    final current = ref.read(maskUiProvider(widget.assetId)).hoverId;
    if (v) {
      _ui.setHover(_m.id);
    } else if (current == _m.id) {
      _ui.setHover(null);
    }
  }

  void _toggleOverlay() {
    if (widget.overlayShown) {
      _ui.setShowOverlay(false);
    } else {
      _ui
        ..select(_m.id)
        ..setShowOverlay(true);
    }
  }

  void _delete() {
    final name = _m.name;
    final ctl = ref.read(editorProvider(widget.assetId).notifier);
    _cmds.delete(_m.id);
    showToast(
      context,
      'Deleted $name.',
      actionLabel: 'Undo',
      onAction: ctl.undo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = widget.selected || _hover;
    final supported = _m.isSupported;
    final iconColor = widget.selected ? t.accent : t.textSecondary;
    final btn = widget.touch ? 36.0 : 28.0;
    final iconSize = widget.touch ? 18.0 : 16.0;
    Widget action(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      bool on = false,
    }) => LumenIconButton(
      icon: icon,
      tooltip: tip,
      size: btn,
      iconSize: iconSize,
      selected: on,
      onPressed: onTap,
    );
    final name = _renaming
        ? CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _finishRename(commit: false),
            },
            child: TextField(
              controller: _name,
              focusNode: _nameFocus,
              autofocus: true,
              maxLength: 40,
              style: LumenType.body(touch: widget.touch)
                  .copyWith(color: t.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Sp.s1_5,
                  vertical: Sp.s1,
                ),
                filled: true,
                fillColor: t.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Rad.xs),
                  borderSide: BorderSide(color: t.accent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Rad.xs),
                  borderSide: BorderSide(color: t.accent),
                ),
              ),
              onSubmitted: (_) => _finishRename(commit: true),
              onTapOutside: (_) => _finishRename(commit: true),
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _m.name,
                overflow: TextOverflow.ellipsis,
                style:
                    (widget.selected
                            ? LumenType.bodyStrong(touch: widget.touch)
                            : LumenType.body(touch: widget.touch))
                        .copyWith(
                          color: active ? t.textPrimary : t.textSecondary,
                        ),
              ),
              if (!supported)
                Text(
                  'Made in a newer version',
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.caption().copyWith(color: t.textTertiary),
                ),
            ],
          );
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Semantics(
        selected: widget.selected,
        label: '${_m.name}, ${_m.kind.menuLabel} mask',
        hint: supported ? 'Double-click, long-press or F2 to rename' : null,
        child: FocusableActionDetector(
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.f2): _RenameIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => _ui.select(_m.id),
            ),
            _RenameIntent: CallbackAction<_RenameIntent>(
              onInvoke: (_) => _startRename(),
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onLongPress: widget.touch ? _startRename : null,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              curve: Motion.standard,
              height: widget.touch ? 48 : 36,
              padding: const EdgeInsets.only(left: Sp.s2),
              decoration: BoxDecoration(
                color: widget.selected
                    ? t.accentTint
                    : (_hover ? t.hoverOverlay : Colors.transparent),
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(Rad.sm + 2),
                      border: Border.all(color: t.focusRing, width: 2),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(_m.kind.icon, size: 16, color: iconColor),
                  const SizedBox(width: Sp.s2),
                  Expanded(child: name),
                  if (_m.kind.isAi) ...[
                    const SizedBox(width: Sp.s1),
                    const AiGlyph(size: 12),
                  ],
                  const SizedBox(width: Sp.s1),
                  action(
                    widget.overlayShown ? LucideIcons.eye : LucideIcons.eyeOff,
                    widget.overlayShown ? 'Hide overlay  O' : 'Show overlay  O',
                    supported ? _toggleOverlay : null,
                    on: widget.overlayShown,
                  ),
                  action(
                    LucideIcons.contrast,
                    'Invert',
                    supported ? () => _cmds.setInvert(_m.id, !_m.invert) : null,
                    on: _m.invert,
                  ),
                  action(
                    LucideIcons.copy,
                    'Duplicate',
                    supported && widget.canDuplicate
                        ? () => _cmds.duplicate(_m.id)
                        : null,
                  ),
                  action(LucideIcons.trash2, 'Delete', _delete),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// F2 on a focused row starts renaming it.
class _RenameIntent extends Intent {
  const _RenameIntent();
}
