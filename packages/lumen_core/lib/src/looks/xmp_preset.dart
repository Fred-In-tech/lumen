/// Lightroom Classic / Lightroom / Camera Raw presets saved as `.xmp`.
library;

import 'lightroom_mapping.dart';
import 'safe_xml.dart';

const String kCrsNamespace = 'http://ns.adobe.com/camera-raw-settings/1.0/';
const String kRdfNamespace = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
const String _xmlNamespace = 'http://www.w3.org/XML/1998/namespace';

/// Thrown for a file that is XML but not a Lightroom preset.
class PresetFormatException implements Exception {
  const PresetFormatException(this.message);
  final String message;

  @override
  String toString() => 'PresetFormatException: $message';
}

/// Reads the `crs:` settings of an XMP preset (attributes and child
/// elements of the top-level `rdf:Description`). Nested structures (masks,
/// the profile `crs:Look` with its own parameters) become [CrsStruct] and
/// are never flattened into the preset.
LightroomPresetData readXmpPreset(String text) {
  final XmlElement root;
  try {
    root = parseSafeXml(text);
  } on XmlFormatException catch (e) {
    throw PresetFormatException(e.message);
  }
  final rdf = root.find(kRdfNamespace, 'RDF');
  if (rdf == null) {
    throw const PresetFormatException('Not a Lightroom preset (no RDF).');
  }
  for (final d in rdf.elements) {
    if (d.uri != kRdfNamespace || d.local != 'Description') continue;
    final settings = <String, Object?>{};
    d.attributes.forEach((k, v) {
      final bar = k.indexOf('|');
      if (k.substring(0, bar) == kCrsNamespace) {
        settings[k.substring(bar + 1)] = v;
      }
    });
    for (final e in d.elements) {
      if (e.uri == kCrsNamespace) settings[e.local] = _value(e);
    }
    if (settings.isEmpty) continue;
    String? str(String key) {
      final v = settings[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return LightroomPresetData(
      settings: settings,
      name: str('Name'),
      group: str('Group'),
    );
  }
  throw const PresetFormatException(
    'Not a Lightroom preset (no Camera Raw settings).',
  );
}

/// A `crs:` property element: text, a list (`rdf:Seq` / `rdf:Bag`), a
/// language alternative (`rdf:Alt`, the x-default entry) or a structure.
Object? _value(XmlElement e) {
  if (e.elements.isEmpty) return e.text;
  final seq = e.child(kRdfNamespace, 'Seq') ?? e.child(kRdfNamespace, 'Bag');
  if (seq != null) {
    return [
      for (final li in seq.elements)
        if (li.elements.isEmpty) li.text else CrsStruct(_structName(li)),
    ];
  }
  final alt = e.child(kRdfNamespace, 'Alt');
  if (alt != null) {
    final items = alt.elements.toList();
    if (items.isEmpty) return '';
    final def = items.firstWhere(
      (li) => li.attr(_xmlNamespace, 'lang') == 'x-default',
      orElse: () => items.first,
    );
    return def.text;
  }
  return CrsStruct(_structName(e));
}

String? _structName(XmlElement e) {
  final d = e.child(kRdfNamespace, 'Description') ?? e;
  final attr = d.attr(kCrsNamespace, 'Name');
  if (attr != null) return attr;
  final n = d.child(kCrsNamespace, 'Name');
  if (n == null) return null;
  final v = _value(n);
  return v is String ? v : null;
}
