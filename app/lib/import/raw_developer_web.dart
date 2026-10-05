import 'dart:typed_data';

import 'package:lumen/import/raw_developer_types.dart';

/// Web: the browser has no camera RAW decoder.
class PlatformRawDeveloper implements RawDeveloper {
  const PlatformRawDeveloper();

  @override
  Future<Uint8List> develop(Uint8List raw, {required String extension}) =>
      throw const RawDevelopException(kRawUnsupportedMessage);
}
