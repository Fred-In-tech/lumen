import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/toast.dart';

const kPromptSuggestions = ['Brighter face', 'Make the sky pop', 'Moodier', 'Golden hour', 'Clean & bright', 'Warmer'];

/// "Describe an edit…" bar (DESIGN.md §4.10).
class PromptBar extends ConsumerStatefulWidget {
  const PromptBar({super.key, required this.session, this.width = 520});

  final EditorSession session;
  final double width;

  @override
  ConsumerState<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends ConsumerState<PromptBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _last;
  String? _result;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit([String? override]) async {
    final instruction = (override ?? _text.text).trim();
    if (instruction.isEmpty) return;
    _last = instruction;
    _text.clear();
    final r = await runInstruction(ref, widget.session, instruction);
    if (!mounted || r == null) return;
    final n = r.outcome.changes.length;
    if (n == 0) {
      final tips = r.outcome.suggestions.isEmpty ? '' : ' Try: ${r.outcome.suggestions.take(3).join(', ')}.';
      showToast(context, 'I couldn’t turn that into an edit.$tips');
      setState(() => _result = null);
    } else {
      setState(() => _result = '$n ${n == 1 ? 'slider' : 'sliders'} changed');
      Future<void>.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _result = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final busy = ref.watch(editorProvider(widget.session.assetId).select((s) => s.value?.aiBusy ?? false));
    final status = ref.watch(editorProvider(widget.session.assetId).select((s) => s.value?.aiStatus));
    final focused = _focus.hasFocus;
    return SizedBox(
      width: widget.width,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (focused && !busy)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.s2),
            child: Wrap(spacing: Sp.s1_5, runSpacing: Sp.s1_5, alignment: WrapAlignment.center, children: [
              for (final s in kPromptSuggestions)
                GestureDetector(
                  onTap: () => _submit(s),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: t.surface3, borderRadius: BorderRadius.circular(Rad.pill), boxShadow: Elevation.e2),
                      child: Text(s, style: LumenType.label().copyWith(color: t.textPrimary)),
                    ),
                  ),
                ),
            ]),
          ),
        if (_result != null && !busy)
          Container(
            margin: const EdgeInsets.only(bottom: Sp.s2),
            padding: const EdgeInsets.symmetric(horizontal: Sp.s3, vertical: Sp.s1_5),
            decoration: BoxDecoration(color: t.surface3, borderRadius: BorderRadius.circular(Rad.pill), boxShadow: Elevation.e2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const AiGlyph(size: 12),
              const SizedBox(width: Sp.s1_5),
              Text(_result!, style: LumenType.caption().copyWith(color: t.textPrimary)),
              const SizedBox(width: Sp.s3),
              GestureDetector(
                onTap: () {
                  ref.read(editorProvider(widget.session.assetId).notifier).undo();
                  setState(() => _result = null);
                },
                child: Text('Undo', style: LumenType.caption().copyWith(color: t.accent)),
              ),
            ]),
          ),
        AnimatedOpacity(
          duration: Motion.fast,
          opacity: focused || busy ? 1 : 0.88,
          child: Container(
            height: Layout.promptBarHeight,
            padding: const EdgeInsets.only(left: Sp.s3, right: Sp.s1_5),
            decoration: BoxDecoration(
              color: t.surface3,
              borderRadius: BorderRadius.circular(Rad.lg),
              boxShadow: Elevation.e2,
              border: Border.all(color: focused ? const Color(0xFFFF894B) : t.line),
            ),
            child: Row(children: [
              const AiGlyph(size: 18),
              const SizedBox(width: Sp.s2),
              Expanded(
                child: busy
                    ? Text(status ?? 'Working…', style: LumenType.body().copyWith(color: t.textSecondary))
                    : CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                            if (_text.text.isEmpty && _last != null) _text.text = _last!;
                          },
                          const SingleActivator(LogicalKeyboardKey.escape): _focus.unfocus,
                        },
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          style: LumenType.body(touch: true).copyWith(fontSize: 14, color: t.textPrimary),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Describe an edit… “warmer, lift the shadows”',
                            hintStyle: LumenType.body(touch: true).copyWith(fontSize: 14, color: t.textTertiary),
                          ),
                          maxLength: 500,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
              ),
              _SendButton(enabled: !busy && _text.text.trim().isNotEmpty, onTap: _submit),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Apply edit',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: enabled ? LumenTokens.aiGradient : null,
            color: enabled ? null : t.surface2,
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.arrowUp, size: 18, color: enabled ? t.textOnAccent : t.textDisabled),
        ),
      ),
    );
  }
}
