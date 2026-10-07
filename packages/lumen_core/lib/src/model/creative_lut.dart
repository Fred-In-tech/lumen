/// A creative 3D LUT attached to an edit or a preset, by reference.
///
/// The LUT data (`CubeLut`) lives in the user's LUT library, keyed by
/// [hash] (`CubeLut.contentHash`). Edits and presets only store the
/// reference, so a photo opened on a machine without that LUT renders
/// without it (see `DevelopContext.lutSize`) instead of failing.
class LutRef {
  const LutRef({required this.hash, required this.name, this.amount = 100});

  /// Returns null for anything that is not a usable reference.
  static LutRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final hash = json['hash'];
    if (hash is! String || !isValidHash(hash)) return null;
    final name = json['name'];
    final amount = json['amount'];
    return LutRef(
      hash: hash,
      name: name is String && name.trim().isNotEmpty ? name : 'LUT',
      amount: amount is num ? clampAmount(amount.toDouble()) : 100,
    );
  }

  /// Content hash of the LUT data: 16 lowercase hex digits.
  final String hash;

  /// Display name (the .cube TITLE or file name).
  final String name;

  /// Strength 0–100 (%): 0 = off, 100 = the LUT's full effect.
  final double amount;

  static bool isValidHash(String h) => RegExp(r'^[0-9a-f]{16}$').hasMatch(h);

  static double clampAmount(double v) =>
      v.isNaN ? 100 : v.clamp(0, 100).toDouble();

  LutRef copyWith({String? name, double? amount}) => LutRef(
    hash: hash,
    name: name ?? this.name,
    amount: amount == null ? this.amount : clampAmount(amount),
  );

  Map<String, Object?> toJson() => {
    'hash': hash,
    'name': name,
    'amount': amount,
  };

  @override
  bool operator ==(Object other) =>
      other is LutRef &&
      other.hash == hash &&
      other.name == name &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(hash, name, amount);

  @override
  String toString() => 'LutRef($name, $hash, $amount%)';
}
