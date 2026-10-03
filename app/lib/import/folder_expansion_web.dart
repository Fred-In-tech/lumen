import 'package:cross_file/cross_file.dart';

/// Browsers deliver files, never folder paths.
Future<List<XFile>> expandFolders(
  List<XFile> items, {
  int limit = 2000,
}) async => items;
