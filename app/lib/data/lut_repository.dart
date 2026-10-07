import 'package:lumen_core/lumen_core.dart';

/// The user's LUT library: `.cube` tables stored once per content hash
/// (`CubeLut.contentHash`). Looks, presets and edits reference them by
/// hash ([LutRef]).
abstract interface class LutRepository {
  /// Stores [lut] (a no-op when the same table is already stored).
  Future<void> save(CubeLut lut);

  /// The stored LUT with [hash], or null.
  Future<CubeLut?> load(String hash);

  /// Hashes of every stored LUT.
  Future<Set<String>> hashes();
}

/// Web and tests: the library lives in memory for the session.
class MemoryLutRepository implements LutRepository {
  final Map<String, CubeLut> _luts = {};

  @override
  Future<void> save(CubeLut lut) async => _luts[lut.contentHash] = lut;

  @override
  Future<CubeLut?> load(String hash) async => _luts[hash];

  @override
  Future<Set<String>> hashes() async => Set.unmodifiable(_luts.keys);
}
