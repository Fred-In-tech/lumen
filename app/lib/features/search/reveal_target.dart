import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/search/reveal.dart';

/// Wraps a control so search can reveal it: scrolls it into view and flashes
/// an accent highlight when [id] is revealed.
class RevealTarget extends ConsumerStatefulWidget {
  const RevealTarget({
    super.key,
    required this.assetId,
    required this.id,
    required this.child,
  });

  final String assetId;
  final String id;
  final Widget child;

  @override
  ConsumerState<RevealTarget> createState() => _RevealTargetState();
}

class _RevealTargetState extends ConsumerState<RevealTarget> {
  bool _flash = false;

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: Motion.of(context, Motion.panel),
        curve: Motion.expoOut,
      );
      setState(() => _flash = true);
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _flash = false);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    // Built because of the reveal (section just opened, module just shown).
    final r = ref.read(revealControlProvider(widget.assetId));
    if (r != null && r.entry.id == widget.id) _reveal();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RevealRequest?>(revealControlProvider(widget.assetId), (_, r) {
      if (r != null && r.entry.id == widget.id) _reveal();
    });
    final t = context.tokens;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      decoration: BoxDecoration(
        color: _flash ? t.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(Rad.sm),
      ),
      child: widget.child,
    );
  }
}

/// A token that changes when a control in [ids] is revealed (sections open
/// on it), else null.
int? revealSignal(RevealRequest? r, Iterable<String> ids) =>
    r != null && ids.contains(r.entry.id) ? r.serial : null;
