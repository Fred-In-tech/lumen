// Float (high-bit-depth) decode of RAW, 16-bit PNG and 10-bit HEIC through
// the OS decoder. Apple platforms only; elsewhere photos keep the 8-bit path.
export 'float_decoder_types.dart';
export 'float_decoder_web.dart' if (dart.library.io) 'float_decoder_io.dart';
