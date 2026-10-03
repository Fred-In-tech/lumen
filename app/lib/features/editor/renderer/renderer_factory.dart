import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';

/// Builds the renderer for an editor session. The GPU renderer is installed
/// here once available; tests override with a CPU or fake renderer.
final photoRendererFactoryProvider = Provider<PhotoRenderer Function()>((ref) => CpuPhotoRenderer.new);
