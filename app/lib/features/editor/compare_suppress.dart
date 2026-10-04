import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

/// Params turned off while the user holds a section's compare eye (Evoto's
/// press-and-hold to see the photo without one feature group). Develop ids
/// and portrait ids may be mixed. Not part of the document or history.
class CompareSuppressNotifier extends Notifier<Set<String>> {
  CompareSuppressNotifier(this.assetId);

  final String assetId;

  @override
  Set<String> build() => const {};

  void hold(Set<String> ids) => state = Set.unmodifiable(ids);

  void release() => state = const {};
}

final compareSuppressProvider =
    NotifierProvider.family<CompareSuppressNotifier, Set<String>, String>(
      CompareSuppressNotifier.new,
    );

/// [s] with the [ids] in [suppress] turned off (develop params back to their
/// defaults, portrait params removed from every group and person).
DevelopSettings withSuppressed(DevelopSettings s, Set<String> suppress) {
  if (suppress.isEmpty) return s;
  final develop = [
    for (final id in suppress)
      if (ParamRegistry.contains(id)) id,
  ];
  final portrait = {
    for (final id in suppress)
      if (PortraitRegistry.tryById(id) != null) id,
  };
  return s
      .resetParams(develop)
      .copyWith(portrait: s.portrait.withoutParams(portrait));
}
