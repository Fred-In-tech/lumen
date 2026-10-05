import 'dart:typed_data';

/// Shown when this platform has no camera RAW decoder.
const kRawUnsupportedMessage =
    "RAW photos aren't supported on this device yet.";

/// Thrown when a RAW file cannot be developed; [message] is user-facing.
class RawDevelopException implements Exception {
  const RawDevelopException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Develops camera RAW into something the 8-bit pixel pipeline can decode.
/// Swapped for a fake in tests.
abstract interface class RawDeveloper {
  /// Develops [raw] once at full resolution (camera white balance, default
  /// rendering, orientation applied, sRGB) and returns it as a JPEG that
  /// carries the camera's EXIF. [extension] is the RAW type, e.g. `cr3`.
  ///
  /// Throws [RawDevelopException] when the platform has no decoder or the
  /// file cannot be read.
  Future<Uint8List> develop(Uint8List raw, {required String extension});
}
