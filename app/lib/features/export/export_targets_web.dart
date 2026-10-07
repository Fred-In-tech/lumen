import 'package:share_plus/share_plus.dart';

import 'package:lumen/features/export/export_service.dart';

Future<String?> chooseExportFolder({String? initial}) async => null;

Future<List<String>> writeExports(
  String folder,
  List<ExportedFile> files,
) async => const [];

Future<String> shareStagingFolder() async => '';

Future<void> sharePaths(List<String> paths) async {}

String _mime(String name) => name.endsWith('.png')
    ? 'image/png'
    : (name.endsWith('.tif') ? 'image/tiff' : 'image/jpeg');

/// Web: the share plugin falls back to a browser download.
Future<void> shareExports(List<ExportedFile> files) => SharePlus.instance.share(
  ShareParams(
    files: [
      for (final f in files)
        XFile.fromData(f.bytes, name: f.fileName, mimeType: _mime(f.fileName)),
    ],
    downloadFallbackEnabled: true,
  ),
);

const bool kExportNeedsFolder = false;
