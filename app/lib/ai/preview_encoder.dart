import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';

/// Re-encodes pixels as a JPEG with no metadata (so no EXIF/GPS leaves the device).
Future<Uint8List> encodeJpegNoMetadata(RgbaBuffer buf, {int quality = 88}) => Isolate.run(() {
      final image = img.Image.fromBytes(
        width: buf.width,
        height: buf.height,
        bytes: buf.data.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    });
