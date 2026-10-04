import 'dart:math' as math;

/// One SSD anchor, normalized to the detector input (0..1).
class SsdAnchor {
  const SsdAnchor(this.centerX, this.centerY, this.width, this.height);

  final double centerX;
  final double centerY;
  final double width;
  final double height;
}

/// Thrown when no known anchor layout produces the anchor count a detector's
/// output tensor reports.
class AnchorLayoutException implements Exception {
  const AnchorLayoutException(this.message);
  final String message;

  @override
  String toString() => 'AnchorLayoutException: $message';
}

/// MediaPipe `SsdAnchorsCalculator` options (the subset BlazeFace uses).
///
/// The input size is taken from the detector's input tensor at load time
/// ([withInputSize] / [resolve]); the named configs only carry the layout.
class SsdAnchorConfig {
  const SsdAnchorConfig({
    required this.name,
    required this.inputWidth,
    required this.inputHeight,
    required this.strides,
    this.minScale = 0.1484375,
    this.maxScale = 0.75,
    this.aspectRatios = const [1.0],
    this.interpolatedScaleAspectRatio = 1.0,
    this.anchorOffsetX = 0.5,
    this.anchorOffsetY = 0.5,
    this.fixedAnchorSize = true,
  });

  /// BlazeFace short-range (inside `face_landmarker.task`): 128², 896 anchors
  /// = 16×16×2 + 8×8×6.
  static const shortRange = SsdAnchorConfig(
    name: 'short_range',
    inputWidth: 128,
    inputHeight: 128,
    strides: [8, 16, 16, 16],
  );

  /// BlazeFace full-range: one stride-4 layer, one anchor per cell
  /// (192² → 2304 anchors in the original release).
  static const fullRange = SsdAnchorConfig(
    name: 'full_range',
    inputWidth: 192,
    inputHeight: 192,
    strides: [4],
    interpolatedScaleAspectRatio: 0,
  );

  static const knownLayouts = [shortRange, fullRange];

  final String name;
  final int inputWidth;
  final int inputHeight;
  final List<int> strides;
  final double minScale;
  final double maxScale;
  final List<double> aspectRatios;

  /// > 0 adds one extra anchor per layer at the geometric-mean scale.
  final double interpolatedScaleAspectRatio;
  final double anchorOffsetX;
  final double anchorOffsetY;

  /// BlazeFace uses unit anchors: the regressor carries absolute sizes.
  final bool fixedAnchorSize;

  SsdAnchorConfig withInputSize(int width, int height) => SsdAnchorConfig(
    name: name,
    inputWidth: width,
    inputHeight: height,
    strides: strides,
    minScale: minScale,
    maxScale: maxScale,
    aspectRatios: aspectRatios,
    interpolatedScaleAspectRatio: interpolatedScaleAspectRatio,
    anchorOffsetX: anchorOffsetX,
    anchorOffsetY: anchorOffsetY,
    fixedAnchorSize: fixedAnchorSize,
  );

  int get _anchorsPerLayer =>
      aspectRatios.length + (interpolatedScaleAspectRatio > 0 ? 1 : 0);

  /// Anchor count without generating them.
  int get anchorCount {
    var total = 0;
    for (final g in _strideGroups()) {
      final fw = (inputWidth / g.stride).ceil();
      final fh = (inputHeight / g.stride).ceil();
      total += fw * fh * g.layers * _anchorsPerLayer;
    }
    return total;
  }

  /// Picks the known layout that yields [anchorCount] at the detector's real
  /// input size (read from the tensors, never assumed).
  static SsdAnchorConfig resolve({
    required int inputWidth,
    required int inputHeight,
    required int anchorCount,
    List<SsdAnchorConfig> layouts = knownLayouts,
  }) {
    for (final layout in layouts) {
      final sized = layout.withInputSize(inputWidth, inputHeight);
      if (sized.anchorCount == anchorCount) return sized;
    }
    throw AnchorLayoutException(
      'No anchor layout gives $anchorCount anchors at '
      '${inputWidth}x$inputHeight (tried ${layouts.map((l) => l.name)})',
    );
  }

  /// Generates anchors in MediaPipe order (stride group → row → column →
  /// anchor), matching the regressor's anchor axis.
  List<SsdAnchor> generate() {
    final out = <SsdAnchor>[];
    var layerIndex = 0;
    for (final g in _strideGroups()) {
      final sizes = <(double, double)>[];
      for (var l = layerIndex; l < layerIndex + g.layers; l++) {
        final scale = _scaleAt(l);
        for (final ar in aspectRatios) {
          sizes.add(_size(scale, ar));
        }
        if (interpolatedScaleAspectRatio > 0) {
          final next = l == strides.length - 1 ? 1.0 : _scaleAt(l + 1);
          sizes.add(
            _size(math.sqrt(scale * next), interpolatedScaleAspectRatio),
          );
        }
      }
      layerIndex += g.layers;
      final fw = (inputWidth / g.stride).ceil();
      final fh = (inputHeight / g.stride).ceil();
      for (var y = 0; y < fh; y++) {
        for (var x = 0; x < fw; x++) {
          for (final (w, h) in sizes) {
            out.add(
              SsdAnchor(
                (x + anchorOffsetX) / fw,
                (y + anchorOffsetY) / fh,
                fixedAnchorSize ? 1.0 : w,
                fixedAnchorSize ? 1.0 : h,
              ),
            );
          }
        }
      }
    }
    return List.unmodifiable(out);
  }

  double _scaleAt(int layer) => strides.length == 1
      ? (minScale + maxScale) / 2
      : minScale + (maxScale - minScale) * layer / (strides.length - 1);

  static (double, double) _size(double scale, double aspect) {
    final r = math.sqrt(aspect);
    return (scale * r, scale / r);
  }

  /// Consecutive layers with the same stride share one feature map.
  List<({int stride, int layers})> _strideGroups() {
    final groups = <({int stride, int layers})>[];
    var i = 0;
    while (i < strides.length) {
      var j = i;
      while (j < strides.length && strides[j] == strides[i]) {
        j++;
      }
      groups.add((stride: strides[i], layers: j - i));
      i = j;
    }
    return groups;
  }
}
