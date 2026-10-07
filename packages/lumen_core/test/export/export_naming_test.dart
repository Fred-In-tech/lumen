import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  final day = DateTime(2026, 3, 9, 14, 5);

  test('expands every token', () {
    expect(
      exportBaseName(
        '{date}_{name}_{seq}_{preset}',
        original: 'IMG_2041.CR3',
        date: day,
        seq: 7,
        total: 120,
        preset: 'Web (2048 px JPEG 85)',
      ),
      '2026-03-09_IMG_2041_007_Web (2048 px JPEG 85)',
    );
  });

  test('sequence is padded to the batch size, at least two digits', () {
    String n(int seq, int total) => exportBaseName(
      '{seq}',
      original: 'a.jpg',
      date: day,
      seq: seq,
      total: total,
      preset: 'p',
    );
    expect(n(3, 1), '03');
    expect(n(3, 9), '03');
    expect(n(42, 1000), '0042');
  });

  test('removes path separators and characters that break file systems', () {
    expect(
      exportBaseName(
        '../{name}/x:y*?"<>|',
        original: 'a.b.jpg',
        date: day,
        seq: 1,
        total: 1,
        preset: 'p',
      ),
      '.._a.b_x_y______',
    );
  });

  test('empty results fall back to the original name; unknown tokens stay', () {
    expect(
      exportBaseName(
        '  ',
        original: 'IMG.jpg',
        date: day,
        seq: 1,
        total: 1,
        preset: 'p',
      ),
      'IMG',
    );
    expect(
      exportBaseName(
        '{name}{oops}',
        original: 'IMG',
        date: day,
        seq: 1,
        total: 1,
        preset: 'p',
      ),
      'IMG{oops}',
    );
  });

  test('file name adds the extension, default template is the old one', () {
    expect(
      exportFileNameFor(
        kDefaultNaming,
        original: 'IMG_2041.HEIC',
        format: ExportFileFormat.tiff16,
        date: day,
        seq: 1,
        total: 1,
        preset: 'Print',
      ),
      'IMG_2041_edit.tif',
    );
  });

  test('unique names within a batch', () {
    final taken = <String>{};
    expect(uniqueName('a.jpg', taken), 'a.jpg');
    expect(uniqueName('a.jpg', taken), 'a (2).jpg');
    expect(uniqueName('a.jpg', taken), 'a (3).jpg');
    expect(uniqueName('noext', taken), 'noext');
    expect(uniqueName('noext', taken), 'noext (2)');
  });
}
