// Disk cache of float previews (docs/HIGH_BIT_DEPTH.md, "Preview cache"):
// files under the app's caches directory on platforms with dart:io, nothing
// on the web.
export 'float_preview_cache_types.dart';
export 'float_preview_cache_web.dart'
    if (dart.library.io) 'float_preview_cache_io.dart';
