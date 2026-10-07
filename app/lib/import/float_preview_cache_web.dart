import 'package:lumen/import/float_preview_cache_types.dart';
import 'package:lumen/platform/platform_info.dart';

/// Web: no float decoder, so nothing to cache.
FloatPreviewCache platformFloatPreviewCache({PlatformInfo? platform}) =>
    const NoFloatPreviewCache();
