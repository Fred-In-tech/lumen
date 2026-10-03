import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen/widgets/toast.dart';

/// Auto button, AI amount, offline badge and "What I changed" (DESIGN.md §3.3).
class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key, required this.session, this.touch = false});

  final EditorSession session;
  final bool touch;

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  double _amount = 100;
  bool _explainOpen = true;

  Future<void> _auto(AiStyle style) async {
    setState(() {
      _amount = 100;
      _explainOpen = true;
    });
    final r = await runAutoEdit(ref, widget.session, style: style);
    if (!mounted || r == null) return;
    final n = r.outcome.changes.length;
    if (n == 0) {
      showToast(context, 'This photo already looks balanced. Nothing to change.');
    } else if (r.record.degradedReason != null && r.record.degradedReason != 'offline') {
      showToast(context, 'AI wasn’t reachable, so I used Basic auto.', kind: ToastKind.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final id = widget.session.assetId;
    final state = ref.watch(editorProvider(id)).value;
    final status = ref.watch(gatewayStatusProvider).value;
    final vision = status?.visionAvailable ?? false;
    final ai = state?.doc.ai;
    final busy = state?.aiBusy ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: LumenButton(
            label: busy ? (state?.aiStatus ?? 'Developing…') : 'Auto',
            icon: busy
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: vision ? t.textOnAccent : t.textPrimary))
                : AiGlyph(size: 16, neutral: true),
            kind: vision ? ButtonKind.ai : ButtonKind.secondary,
            height: widget.touch ? 48 : 40,
            expand: true,
            tooltip: vision
                ? 'AI reads the photo and sets every slider. Shortcut: A'
                : 'Basic auto runs on this device. AI styles and prompts need the gateway.',
            onPressed: busy || state == null ? null : () => _auto(AiStyle.fromId(ai?.style ?? 'natural') ?? AiStyle.natural),
          ),
        ),
      ]),
      if (!vision) ...[
        const SizedBox(height: Sp.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: status?.message ?? 'Checking the AI gateway…',
            child: StatusPill(label: 'Basic auto (offline)', leading: Icon(LucideIcons.cloudOff, size: 14, color: t.textSecondary)),
          ),
        ),
      ],
      if (ai != null && ai.postAi != null) ...[
        const SizedBox(height: Sp.s2),
        LumenSlider(
          label: 'AI amount',
          value: _amount,
          min: kAiAmountMin,
          max: kAiAmountMax,
          defaultValue: 100,
          bipolar: false,
          touch: widget.touch,
          onChangeStart: () => ref.read(editorProvider(id).notifier).beginGesture('AI amount'),
          onChanged: (v) {
            setState(() => _amount = v);
            ref.read(editorProvider(id).notifier).preview(applyAiAmount(pre: ai.preAi, ai: ai.postAi!, percent: v));
          },
          onChangeEnd: () => ref.read(editorProvider(id).notifier).commitGesture(label: 'AI amount ${_amount.round()}%', kind: HistoryKind.ai),
          onCommit: (v) {
            setState(() => _amount = v);
            ref.read(editorProvider(id).notifier).commit(
                  applyAiAmount(pre: ai.preAi, ai: ai.postAi!, percent: v),
                  label: 'AI amount ${v.round()}%',
                  kind: HistoryKind.ai,
                );
          },
        ),
        if (ai.changes.isNotEmpty) _Explain(record: ai, open: _explainOpen, onToggle: () => setState(() => _explainOpen = !_explainOpen)),
      ],
    ]);
  }
}

class _Explain extends StatelessWidget {
  const _Explain({required this.record, required this.open, required this.onToggle});

  final AiRecord record;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final model = record.engine != 'local';
    final lines = record.changes.where((c) => c.reason.isNotEmpty).take(6).toList();
    return Container(
      margin: const EdgeInsets.only(top: Sp.s2),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border(left: BorderSide(color: model ? const Color(0xFFFF894B) : t.lineStrong, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(Sp.s3, Sp.s2, Sp.s3, Sp.s2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: onToggle,
          child: Row(children: [
            AiGlyph(size: 13, neutral: !model),
            const SizedBox(width: Sp.s1_5),
            Expanded(
              child: Text(
                open ? 'What I changed' : '${record.changes.length} changes · Why?',
                style: LumenType.bodyStrong().copyWith(color: t.textPrimary),
              ),
            ),
            Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: t.textTertiary),
          ]),
        ),
        if (open) ...[
          if (record.intent != null && record.intent!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s1),
              child: Text(record.intent!, style: LumenType.body().copyWith(color: t.textSecondary, fontStyle: FontStyle.italic)),
            ),
          for (final c in lines)
            Padding(
              padding: const EdgeInsets.only(top: Sp.s1),
              child: Text('· ${c.reason}', style: LumenType.body().copyWith(color: t.textSecondary)),
            ),
        ],
      ]),
    );
  }
}
