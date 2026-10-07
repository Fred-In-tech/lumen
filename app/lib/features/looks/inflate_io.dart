import 'dart:io';
import 'dart:typed_data';

/// Raw DEFLATE → bytes with `dart:io`'s zlib, stopping as soon as the output
/// passes [maxBytes] (the size the zip declares): input is fed in 4 KB
/// steps, so a zip bomb never gets to allocate more than one step's output
/// beyond the cap.
Uint8List inflateCapped(Uint8List deflated, int maxBytes) {
  final sink = _CappedSink(maxBytes);
  final input = ZLibDecoder(raw: true).startChunkedConversion(sink);
  const step = 4096;
  for (var i = 0; i < deflated.length; i += step) {
    final end = i + step < deflated.length ? i + step : deflated.length;
    input.add(Uint8List.sublistView(deflated, i, end));
  }
  input.close();
  return sink.bytes.takeBytes();
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.max);
  final int max;
  final BytesBuilder bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > max) {
      throw const FormatException('Entry is larger than the archive says.');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
