import 'package:share_plus/share_plus.dart';

import 'package:lumen/features/export/export_service.dart';

Future<String?> chooseExportFolder() async => null;

Future<List<String>> writeExports(
  String folder,
  List<ExportedFile> files,
) async => const [];

/// Web: the share plugin falls back to a browser download.
Future<void> shareExports(List<ExportedFile> files) => SharePlus.instance.share(
  ShareParams(
    files: [
      for (final f in files)
        XFile.fromData(
          f.bytes,
          name: f.fileName,
          mimeType: f.fileName.endsWith('.png') ? 'image/png' : 'image/jpeg',
        ),
    ],
    downloadFallbackEnabled: true,
  ),
);

const bool kExportNeedsFolder = false;
