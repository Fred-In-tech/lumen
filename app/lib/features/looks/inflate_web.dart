import 'dart:typed_data';

/// No zlib on the web build (a demo target): zip bundles are reported as
/// not readable; single preset and LUT files still import.
Uint8List inflateCapped(Uint8List deflated, int maxBytes) =>
    throw const FormatException('Zip bundles cannot be opened here.');
