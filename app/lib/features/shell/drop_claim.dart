/// Nested drop targets all receive a drop. A specific target (a project
/// card) claims it; a catch-all target (the Home page) waits a turn and
/// skips drops someone claimed.
abstract final class DropClaim {
  static int _generation = 0;

  /// Called by the specific target that handles the drop.
  static void claim() => _generation++;

  /// Runs [handle] unless a specific target claims the same drop.
  static Future<void> unlessClaimed(Future<void> Function() handle) async {
    final before = _generation;
    await Future<void>.delayed(Duration.zero);
    if (_generation == before) await handle();
  }
}
