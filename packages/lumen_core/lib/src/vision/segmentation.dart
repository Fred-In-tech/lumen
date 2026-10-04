import 'dart:math' as math;
import 'dart:typed_data';

import 'tensor_sampling.dart';

/// Selfie Multiclass output channels, in model order (its `labels.txt`).
abstract final class SelfieClass {
  static const background = 0;
  static const hair = 1;
  static const bodySkin = 2;
  static const faceSkin = 3;
  static const clothes = 4;
  static const others = 5;
  static const count = 6;
}

/// Per-pixel class probabilities from a raw `[H, W, C]` output: kept when
/// it already holds probabilities (every value in [0, 1], sums ≈ 1), else
/// treated as logits and softmaxed. Returns a new list.
Float32List multiclassProbabilities(Float32List raw, int channels) {
  if (channels < 1 || raw.length % channels != 0) {
    throw ArgumentError('${raw.length} values are not a multiple of $channels');
  }
  final pixels = raw.length ~/ channels;
  var isProb = true;
  for (var p = 0; p < pixels && isProb; p += math.max(1, pixels ~/ 512)) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      final v = raw[p * channels + c];
      if (v < -1e-3 || v > 1 + 1e-3) isProb = false;
      sum += v;
    }
    if ((sum - 1).abs() > 0.05) isProb = false;
  }
  if (isProb) return Float32List.fromList(raw);
  final out = Float32List(raw.length);
  for (var p = 0; p < pixels; p++) {
    final o = p * channels;
    var mx = raw[o];
    for (var c = 1; c < channels; c++) {
      mx = math.max(mx, raw[o + c]);
    }
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      final e = math.exp(raw[o + c] - mx);
      out[o + c] = e;
      sum += e;
    }
    for (var c = 0; c < channels; c++) {
      out[o + c] /= sum;
    }
  }
  return out;
}

/// One segmentation run: class probabilities over a [region] of the source
/// image that was letterboxed into a `width × height` tensor. Samples by
/// source pixel coordinates (continuous; pixel (i, j) covers [i, i+1)).
class SegmentationView {
  SegmentationView({
    required this.probabilities,
    required this.width,
    required this.height,
    required this.channels,
    required this.region,
    this.letterbox = const Letterbox(),
  }) {
    if (probabilities.length != width * height * channels) {
      throw ArgumentError('probabilities do not match ${width}x$height');
    }
  }

  /// `[height, width, channels]`, 0..1.
  final Float32List probabilities;
  final int width;
  final int height;
  final int channels;
  final PixelRegion region;
  final Letterbox letterbox;

  /// Region-relative coordinates (0..1 across the region).
  (double, double) _uv(double sx, double sy) =>
      ((sx - region.left) / region.width, (sy - region.top) / region.height);

  bool contains(double sx, double sy) {
    final (u, v) = _uv(sx, sy);
    return u >= 0 && u <= 1 && v >= 0 && v <= 1;
  }

  /// Bilinear probabilities of [channels] at source point ([sx], [sy])
  /// into [out] (one coordinate computation for all channels).
  void sampleInto(double sx, double sy, List<int> channels, List<double> out) {
    final (u, v) = _uv(sx, sy);
    final lb = letterbox;
    final tx = (lb.left + u.clamp(0.0, 1.0) * (1 - lb.left - lb.right)) * width;
    final ty = (lb.top + v.clamp(0.0, 1.0) * (1 - lb.top - lb.bottom)) * height;
    final px = (tx - 0.5).clamp(
      lb.left * width,
      math.max(lb.left * width, (1 - lb.right) * width - 1),
    );
    final py = (ty - 0.5).clamp(
      lb.top * height,
      math.max(lb.top * height, (1 - lb.bottom) * height - 1),
    );
    final x0 = px.floor(), y0 = py.floor();
    final x1 = math.min(x0 + 1, width - 1), y1 = math.min(y0 + 1, height - 1);
    final fx = px - x0, fy = py - y0;
    final c = this.channels, p = probabilities;
    final i00 = (y0 * width + x0) * c, i10 = (y0 * width + x1) * c;
    final i01 = (y1 * width + x0) * c, i11 = (y1 * width + x1) * c;
    for (var k = 0; k < channels.length; k++) {
      final ch = channels[k];
      final top = p[i00 + ch] + (p[i10 + ch] - p[i00 + ch]) * fx;
      final bot = p[i01 + ch] + (p[i11 + ch] - p[i01 + ch]) * fx;
      out[k] = top + (bot - top) * fy;
    }
  }

  /// Bilinear probability of [channel] at source point ([sx], [sy]);
  /// outside the region the nearest edge value is used.
  double sample(int channel, double sx, double sy) {
    final out = [0.0];
    sampleInto(sx, sy, [channel], out);
    return out[0];
  }

  /// Blend weight: 1 inside, fading to 0 over the outer [feather] fraction
  /// of the region (so per-face crops merge into the whole-image pass
  /// without seams), 0 outside.
  double weight(double sx, double sy, {double feather = 0.1}) {
    final (u, v) = _uv(sx, sy);
    if (u < 0 || u > 1 || v < 0 || v > 1) return 0;
    final d = math.min(math.min(u, 1 - u), math.min(v, 1 - v));
    if (feather <= 0 || d >= feather) return 1;
    final t = d / feather;
    return t * t * (3 - 2 * t);
  }
}

/// How much a per-face [crop] agrees with the [whole]-image pass that a
/// person is there: mean (1 − background) over the crop's central 30 %
/// (inside the face box, since crops are the box × 2.2), as
/// `(crop, whole)`. A crop that loses a person the whole pass sees is
/// distrusted (see `composeAiMasks`).
(double, double) personAgreement(
  SegmentationView whole,
  SegmentationView crop, {
  int samples = 9,
}) {
  var c = 0.0, w = 0.0;
  final r = crop.region;
  for (var j = 0; j < samples; j++) {
    for (var i = 0; i < samples; i++) {
      final sx = r.left + r.width * (0.35 + 0.3 * (i + 0.5) / samples);
      final sy = r.top + r.height * (0.35 + 0.3 * (j + 0.5) / samples);
      c += 1 - crop.sample(SelfieClass.background, sx, sy);
      w += 1 - whole.sample(SelfieClass.background, sx, sy);
    }
  }
  final n = samples * samples;
  return (c / n, w / n);
}
