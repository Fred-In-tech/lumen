import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';

/// Accordion group with modified dot and reset (DESIGN.md §4.2).
class DevelopGroup extends StatefulWidget {
  const DevelopGroup({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
    this.modified = false,
    this.onReset,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;
  final bool modified;
  final VoidCallback? onReset;

  @override
  State<DevelopGroup> createState() => _DevelopGroupState();
}

class _DevelopGroupState extends State<DevelopGroup> {
  late bool _open = widget.initiallyOpen;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dur = Motion.of(context, Motion.base);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Semantics(
            button: true,
            expanded: _open,
            label: widget.title,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: Sp.s4),
                decoration: BoxDecoration(
                  color: _hover ? t.hoverOverlay : Colors.transparent,
                  border: Border(top: BorderSide(color: t.line)),
                ),
                child: Row(
                  children: [
                    AnimatedOpacity(
                      opacity: widget.modified ? 1 : 0,
                      duration: Motion.fast,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: Sp.s2),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: LumenType.heading().copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    if (widget.modified && widget.onReset != null)
                      Tooltip(
                        message: 'Reset ${widget.title}',
                        child: GestureDetector(
                          onTap: widget.onReset,
                          child: Padding(
                            padding: const EdgeInsets.all(Sp.s1),
                            child: Icon(
                              LucideIcons.rotateCcw,
                              size: 14,
                              color: _hover ? t.textSecondary : t.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: Sp.s1),
                    AnimatedRotation(
                      turns: _open ? 0 : -0.25,
                      duration: Motion.fast,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: t.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: dur,
          curve: Motion.expoOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.s4,
                    Sp.s1,
                    Sp.s4,
                    Sp.s4,
                  ),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Small uppercase-free sub-group caption with a hairline ("White balance").
class SubGroupLabel extends StatelessWidget {
  const SubGroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Sp.s3, bottom: Sp.s1),
    child: Text(
      text,
      style: LumenType.caption().copyWith(color: context.tokens.textTertiary),
    ),
  );
}
