import 'dart:isolate';
import 'dart:typed_data';

import 'image_encoder.dart';

/// Encodes in a background isolate so the UI never stalls on big exports.
Future<Uint8List> encodeImage(EncodeRequest request) =>
    Isolate.run(() => encodeImageSync(request));
