// Keeps on-device derived data (face geometry, AI rasters, models) out of OS
// backups. See docs/PHASE2.md (privacy) and research 07 §1.5.
export 'backup_exclusion_web.dart'
    if (dart.library.io) 'backup_exclusion_io.dart';
