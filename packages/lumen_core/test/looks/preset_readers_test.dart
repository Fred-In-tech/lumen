import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'preset_fixtures.dart';

void main() {
  group('safe XML', () {
    test('elements, attributes, namespaces, text, CDATA, entities', () {
      final root = parseSafeXml(
        '<?xml version="1.0"?><!-- c --><a xmlns="urn:x" xmlns:p="urn:p" '
        "p:k='v &amp; w'><b>t&#65;&#x42;<![CDATA[<raw>]]></b><p:c/></a>",
      );
      expect(root.uri, 'urn:x');
      expect(root.attr('urn:p', 'k'), 'v & w');
      expect(root.child('urn:x', 'b')!.text, 'tAB<raw>');
      expect(root.find('urn:p', 'c'), isNotNull);
    });

    test('rejects DOCTYPE and entity declarations (XXE, billion laughs)', () {
      for (final evil in [kXxeXmp, kLaughsXmp]) {
        expect(
          () => parseSafeXml(evil),
          throwsA(
            isA<XmlFormatException>().having(
              (e) => e.message,
              'message',
              contains('DOCTYPE'),
            ),
          ),
        );
      }
    });

    test('rejects malformed and hostile structure', () {
      for (final bad in [
        '<a><b></a>',
        '<a',
        '<a x=1/>',
        '<a x="1" x="2"/>',
        '<p:a/>',
        '<a>&unknown;</a>',
        '<a>&#0;</a>',
        '<a/><b/>',
        'text',
        '',
        '<a><!-- open',
        '<a><![CDATA[x</a>',
      ]) {
        expect(
          () => parseSafeXml(bad),
          throwsA(isA<XmlFormatException>()),
          reason: bad,
        );
      }
      final deep = '${'<a>' * 100}${'</a>' * 100}';
      expect(() => parseSafeXml(deep), throwsA(isA<XmlFormatException>()));
      expect(
        () => parseSafeXml('<a/>', maxChars: 2),
        throwsA(isA<XmlFormatException>()),
      );
      expect(
        () => parseSafeXml('<a><b/><b/><b/></a>', maxElements: 2),
        throwsA(isA<XmlFormatException>()),
      );
    });
  });

  group('XMP presets', () {
    test('Lightroom Classic layout: attributes plus child elements', () {
      final p = readXmpPreset(kBrightAiryXmp);
      expect(p.name, 'Bright & Airy Wedding');
      expect(p.group, 'Weddings');
      expect(p.settings['Exposure2012'], '+0.70');
      expect(p.settings['ToneCurvePV2012'], [
        '0, 18',
        '64, 70',
        '192, 196',
        '255, 250',
      ]);
      // The profile look and the mask stay opaque structures.
      expect(p.settings['Look'], isA<CrsStruct>());
      expect((p.settings['Look']! as CrsStruct).name, 'Adobe Portrait');
      expect(p.settings['MaskGroupBasedCorrections'], [isA<CrsStruct>()]);
    });

    test('settings as child elements, any crs prefix', () {
      final p = readXmpPreset(kBwXmp);
      expect(p.name, 'Classic B&W');
      expect(p.settings['ConvertToGrayscale'], 'True');
      expect(p.settings['GrayMixerBlue'], '-30');
    });

    test('rejects XML that is not a preset, and hostile XML', () {
      for (final bad in [kNotAPresetXmp, '<a/>', kXxeXmp, '<a']) {
        expect(
          () => readXmpPreset(bad),
          throwsA(isA<PresetFormatException>()),
          reason: bad,
        );
      }
    });
  });

  group('lrtemplate presets', () {
    test('reads settings, ZSTR title, flat curve lists, structures', () {
      final p = readLrTemplate(kMoodyFilmLrTemplate);
      expect(p.name, 'Moody Film');
      expect(p.settings['Exposure2012'], -0.35);
      expect(p.settings['WhiteBalance'], 'Custom');
      expect(p.settings['ToneCurvePV2012'], [
        0,
        30,
        70,
        62,
        190,
        196,
        255,
        238,
      ]);
      expect(p.settings['GradientBasedCorrections'], isA<CrsStruct>());
    });

    test('Lua syntax: comments, long strings, keys, escapes, numbers', () {
      final t = parseLuaAssignment(r'''
--[==[ block
comment ]==]
s = { a = "x\"y\n\65", ['b'] = [[long]], [3] = 0x10, c = -1.5e2, d = nil,
  e = true, f = false; g = LOC("$$$/k=Hello"), 'item', 2, }
''');
      expect(t.fields['a'], 'x"y\nA');
      expect(t.fields['b'], 'long');
      expect(t.fields['3'], 16);
      expect(t.fields['c'], -150);
      expect(t.fields['d'], isNull);
      expect(t.fields['e'], isTrue);
      expect(t.fields['f'], isFalse);
      expect(t.fields['g'], 'Hello');
      expect(t.items, ['item', 2]);
    });

    test('never evaluates: code, operators and globals are rejected', () {
      for (final bad in [
        kEvilLrTemplate,
        's = { x = 1 + 2 }',
        's = { x = y }',
        's = { x = "a" .. "b" }',
        'return { }',
        's = 5',
        's = { x = 1 } trailing',
        's = { x = "unterminated }',
        's = { x = 1',
        's = {${'{' * 40}${'}' * 40}}',
      ]) {
        expect(
          () => parseLuaAssignment(bad),
          throwsA(isA<PresetFormatException>()),
          reason: bad,
        );
      }
      expect(
        () => parseLuaAssignment('s = {}', maxChars: 3),
        throwsA(isA<PresetFormatException>()),
      );
    });

    test('rejects templates that are not develop presets', () {
      expect(
        () => readLrTemplate('s = { type = "Export", value = {} }'),
        throwsA(isA<PresetFormatException>()),
      );
      expect(
        () => readLrTemplate('s = { title = "x", value = { } }'),
        throwsA(isA<PresetFormatException>()),
      );
    });
  });

  group('zip bundles', () {
    final files = {
      'Pack/Portraits/Soft.xmp': bytesOf(kBrightAiryXmp),
      'Pack/Film/Moody.lrtemplate': bytesOf(kMoodyFilmLrTemplate),
      '__MACOSX/Pack/._Soft.xmp': bytesOf('junk'),
      'Pack/.DS_Store': bytesOf('junk'),
      'Pack/readme.txt': bytesOf('hello'),
    };

    test('deflated and stored entries, filtered', () {
      for (final deflate in [true, false]) {
        final entries = readZip(
          buildZip(files, deflate: deflate),
          inflate: inflateRaw,
          want: isLookFile,
        );
        expect(entries.map((e) => e.path), [
          'Pack/Portraits/Soft.xmp',
          'Pack/Film/Moody.lrtemplate',
        ]);
        expect(decodeLookText(entries.first.bytes), kBrightAiryXmp);
      }
    });

    test('rejects damaged, encrypted and oversized archives', () {
      void bad(Uint8List zip, {int maxEntryBytes = 1 << 20}) => expect(
        () => readZip(
          zip,
          inflate: inflateRaw,
          want: (_) => true,
          maxEntryBytes: maxEntryBytes,
        ),
        throwsA(isA<ZipFormatException>()),
      );
      bad(bytesOf('not a zip at all, just text that is long enough'));
      bad(buildZip(files, encryptFlag: true));
      bad(buildZip(files, badCrc: true));
      bad(buildZip(files), maxEntryBytes: 100);
      final ok = buildZip(files);
      bad(Uint8List.sublistView(ok, 0, ok.length - 30));
    });

    test('an inflater that overflows its cap fails the entry', () {
      final zip = buildZip({'a.xmp': bytesOf(kBwXmp)});
      expect(
        () => readZip(
          zip,
          inflate: (raw, max) => throw const FormatException('cap'),
          want: (_) => true,
        ),
        throwsA(isA<ZipFormatException>()),
      );
    });
  });
}
