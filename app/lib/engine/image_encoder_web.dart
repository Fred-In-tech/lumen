import 'dart:typed_data';

import 'image_encoder.dart';

/// Web has no isolates: encode inline (after yielding one event-loop turn
/// so a progress UI can paint first).
Future<Uint8List> encodeImage(EncodeRequest request) async {
  await Future<void>.delayed(Duration.zero);
  return encodeImageSync(request);
}
