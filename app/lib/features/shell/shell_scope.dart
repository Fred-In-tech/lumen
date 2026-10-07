import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app shell's context and ref, for work that must outlive the page
/// that starts it (an import keeps going when its page closes).
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.shellContext,
    required this.shellRef,
    required super.child,
  });

  final BuildContext shellContext;
  final WidgetRef shellRef;

  /// The shell's (context, ref), or the caller's own when there is no
  /// shell above (tests that pump a page alone).
  static (BuildContext, WidgetRef) of(BuildContext context, WidgetRef ref) {
    final scope = context.getInheritedWidgetOfExactType<ShellScope>();
    if (scope == null || !scope.shellContext.mounted) return (context, ref);
    return (scope.shellContext, scope.shellRef);
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}
