import '../model/develop_settings.dart';
import 'rgba_buffer.dart';

/// CPU reference implementation of the develop pipeline (engine `lumen-1`).
///
/// The GPU `develop.frag` must match this within the parity thresholds of
/// PLAN.md §6.3. The local auto-tone solver and guards render proxies with it.
///
/// OWNER: render workstream. Signature is a fixed contract; implementation TBD.
RgbaBuffer renderReference(RgbaBuffer source, DevelopSettings settings) {
  throw UnimplementedError(
    'renderReference is implemented by the render workstream (P1.11)',
  );
}
