import 'dart:typed_data';

/// Value used for "no seed reachable" (any distance is smaller).
const double kNoSeedDistance = 1e20;

/// Exact squared Euclidean distance transform (Felzenszwalb & Huttenlocher
/// 2012): for every pixel of a [w]×[h] grid, the squared distance in pixels
/// to the nearest pixel where [seeds] is non-zero. Without any seed every
/// value is ≥ [kNoSeedDistance]. O(w·h).
Float32List squaredDistanceTransform(Uint8List seeds, int w, int h) {
  if (seeds.length != w * h) {
    throw ArgumentError('seeds ${seeds.length} != $w x $h');
  }
  final n = w > h ? w : h;
  final f = Float64List(n);
  final d = Float64List(n);
  final v = Int32List(n);
  final z = Float64List(n + 1);
  final grid = Float64List(w * h);
  // Columns.
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      f[y] = seeds[y * w + x] != 0 ? 0 : kNoSeedDistance;
    }
    _edt1d(f, h, d, v, z);
    for (var y = 0; y < h; y++) {
      grid[y * w + x] = d[y];
    }
  }
  // Rows.
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      f[x] = grid[row + x];
    }
    _edt1d(f, w, d, v, z);
    for (var x = 0; x < w; x++) {
      out[row + x] = d[x];
    }
  }
  return out;
}

/// Lower envelope of parabolas `(q − p)² + f[p]` over `0..n-1`.
void _edt1d(Float64List f, int n, Float64List d, Int32List v, Float64List z) {
  var k = 0;
  v[0] = 0;
  z[0] = double.negativeInfinity;
  z[1] = double.infinity;
  for (var q = 1; q < n; q++) {
    var s = _intersect(f, q, v[k]);
    while (s <= z[k]) {
      k--;
      s = _intersect(f, q, v[k]);
    }
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = double.infinity;
  }
  k = 0;
  for (var q = 0; q < n; q++) {
    while (z[k + 1] < q) {
      k++;
    }
    final dq = q - v[k];
    d[q] = dq * dq + f[v[k]];
  }
}

double _intersect(Float64List f, int q, int p) =>
    ((f[q] + q * q) - (f[p] + p * p)) / (2 * q - 2 * p);
