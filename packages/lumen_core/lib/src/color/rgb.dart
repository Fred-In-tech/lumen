/// An immutable RGB triple (any encoding; callers document which).
class Rgb {
  const Rgb(this.r, this.g, this.b);

  final double r;
  final double g;
  final double b;

  @override
  String toString() => 'Rgb($r, $g, $b)';
}
