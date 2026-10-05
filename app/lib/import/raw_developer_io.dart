import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/import/raw_developer_types.dart';
import 'package:lumen/platform/platform_info_io.dart';

final _log = Logger('RawDeveloper');

const _channel = MethodChannel('lumen/raw');

/// JPEG quality of the rendition. Measured on a 45 MP Canon R5 CR3: about
/// 9 MB and 2–7 s to develop, against 60 MB and 7 s more for PNG.
const double kRawRenditionQuality = 0.98;

/// Develops RAW with the OS decoder on macOS and iOS (`lumen/raw` channel).
/// Files are handed over by path, inside the app container, so the 30–60 MB
/// RAW never crosses the channel.
class PlatformRawDeveloper implements RawDeveloper {
  const PlatformRawDeveloper({this.platform});

  final PlatformInfo? platform;

  @override
  Future<Uint8List> develop(Uint8List raw, {required String extension}) async {
    if (!(platform ?? PlatformInfo.current()).isApple) {
      throw const RawDevelopException(kRawUnsupportedMessage);
    }
    final dir = await Directory.systemTemp.createTemp('lumen_raw');
    try {
      final input = File(p.join(dir.path, 'source.$extension'));
      final output = File(p.join(dir.path, 'rendition.jpg'));
      await input.writeAsBytes(raw);
      await _channel.invokeMethod<void>('develop', {
        'input': input.path,
        'output': output.path,
        'quality': kRawRenditionQuality,
      });
      return await output.readAsBytes();
    } on PlatformException catch (e) {
      _log.warning('RAW develop failed: ${e.code} ${e.message}');
      throw const RawDevelopException(
        'This RAW file could not be developed. The camera may be too new for '
        'this version of the system.',
      );
    } on MissingPluginException {
      // Tests and embedders without the native handler.
      throw const RawDevelopException(kRawUnsupportedMessage);
    } on FileSystemException catch (e) {
      _log.warning('RAW develop I/O failed: ${e.message}');
      throw const RawDevelopException(
        'This RAW file could not be developed (not enough free space?).',
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException catch (e) {
        _log.fine('RAW temp cleanup failed: ${e.message}');
      }
    }
  }
}
