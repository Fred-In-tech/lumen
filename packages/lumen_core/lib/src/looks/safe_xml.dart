/// A small, safe XML reader for preset files (XMP).
///
/// Only what XMP presets use: elements, attributes, text, CDATA,
/// comments, processing instructions and namespaces. Hardened against
/// hostile files: any `<!DOCTYPE` / `<!ENTITY` is rejected (so external
/// and recursive entities cannot exist), only the five predefined and
/// numeric character references are decoded, and input size, nesting
/// depth, element count and attribute count are capped.
library;

/// Thrown for input that is not acceptable XML. [message] is user-facing.
class XmlFormatException implements Exception {
  const XmlFormatException(this.message);
  final String message;

  @override
  String toString() => 'XmlFormatException: $message';
}

/// An element with its namespace resolved.
class XmlElement {
  XmlElement(this.uri, this.local, this.attributes, this.children);

  /// Namespace URI ('' when the name has no namespace).
  final String uri;
  final String local;

  /// Attributes by `'$uri|$local'` (namespace declarations excluded).
  final Map<String, String> attributes;

  /// Child elements and text, in document order (`XmlElement` or `String`).
  final List<Object> children;

  Iterable<XmlElement> get elements => children.whereType<XmlElement>();

  /// Concatenated direct text children, trimmed.
  String get text => children.whereType<String>().join().trim();

  String? attr(String uri, String local) => attributes['$uri|$local'];

  XmlElement? child(String uri, String local) {
    for (final e in elements) {
      if (e.uri == uri && e.local == local) return e;
    }
    return null;
  }

  /// Depth-first search for the first element named [uri] / [local].
  XmlElement? find(String uri, String local) {
    if (this.uri == uri && this.local == local) return this;
    for (final e in elements) {
      final hit = e.find(uri, local);
      if (hit != null) return hit;
    }
    return null;
  }
}

/// Parses [text] into its root element.
XmlElement parseSafeXml(
  String text, {
  int maxChars = 8 * 1024 * 1024,
  int maxDepth = 64,
  int maxElements = 200000,
}) => _Parser(text, maxChars, maxDepth, maxElements).parseDocument();

class _Parser {
  _Parser(this.s, this.maxChars, this.maxDepth, this.maxElements);

  final String s;
  final int maxChars;
  final int maxDepth;
  final int maxElements;
  int i = 0;
  int _count = 0;

  Never _bad(String why) => throw XmlFormatException('Not readable XML: $why.');

  XmlElement parseDocument() {
    if (s.length > maxChars) {
      throw const XmlFormatException('The file is too large to be a preset.');
    }
    if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(s)) {
      throw const XmlFormatException(
        'The file declares a DOCTYPE or entities, which presets never do.',
      );
    }
    if (s.startsWith('﻿')) i = 1;
    XmlElement? root;
    while (true) {
      _skipMisc();
      if (i >= s.length) break;
      if (root != null) _bad('content after the root element');
      if (s.codeUnitAt(i) != 0x3c) _bad('text outside the root element');
      root = _element(const {'xml': 'http://www.w3.org/XML/1998/namespace'}, 0);
    }
    if (root == null) _bad('no root element');
    return root;
  }

  bool _at(String t) => s.startsWith(t, i);

  /// Whitespace, comments and processing instructions between elements.
  void _skipMisc() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        i++;
      } else if (_at('<!--')) {
        _skipPast('-->');
      } else if (_at('<?')) {
        _skipPast('?>');
      } else {
        return;
      }
    }
  }

  void _skipPast(String end) {
    final j = s.indexOf(end, i);
    if (j < 0) _bad('unterminated "${end.substring(0, 1)}" section');
    i = j + end.length;
  }

  static bool _nameChar(int c) =>
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5f ||
      c == 0x2d ||
      c == 0x2e ||
      c == 0x3a ||
      c > 0x7f;

  String _name() {
    final start = i;
    while (i < s.length && _nameChar(s.codeUnitAt(i))) {
      i++;
    }
    if (i == start) _bad('expected a name at offset $start');
    return s.substring(start, i);
  }

  void _ws() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c != 0x20 && c != 0x09 && c != 0x0a && c != 0x0d) return;
      i++;
    }
  }

  XmlElement _element(Map<String, String> scope, int depth) {
    if (depth > maxDepth) _bad('nesting deeper than $maxDepth');
    if (++_count > maxElements) _bad('more than $maxElements elements');
    i++; // <
    final qname = _name();
    final raw = <String, String>{};
    while (true) {
      _ws();
      if (i >= s.length) _bad('unterminated tag <$qname>');
      final c = s.codeUnitAt(i);
      if (c == 0x3e || c == 0x2f) break;
      final an = _name();
      _ws();
      if (i >= s.length || s.codeUnitAt(i) != 0x3d) _bad('attribute $an');
      i++;
      _ws();
      if (i >= s.length) _bad('attribute $an');
      final q = s.codeUnitAt(i);
      if (q != 0x22 && q != 0x27) _bad('unquoted attribute $an');
      final end = s.indexOf(String.fromCharCode(q), i + 1);
      if (end < 0) _bad('unterminated attribute $an');
      if (raw.containsKey(an)) _bad('duplicate attribute $an');
      if (raw.length >= 4096) _bad('too many attributes');
      raw[an] = _decode(s.substring(i + 1, end));
      i = end + 1;
    }
    // Namespace declarations of this element.
    final ns = Map<String, String>.of(scope);
    raw.forEach((k, v) {
      if (k == 'xmlns') ns[''] = v;
      if (k.startsWith('xmlns:')) ns[k.substring(6)] = v;
    });
    (String, String) resolve(String q, {required bool attr}) {
      final c = q.indexOf(':');
      if (c < 0) return (attr ? '' : (ns[''] ?? ''), q);
      final p = q.substring(0, c);
      final uri = ns[p];
      if (uri == null) _bad('undeclared prefix "$p"');
      return (uri, q.substring(c + 1));
    }

    final attrs = <String, String>{};
    raw.forEach((k, v) {
      if (k == 'xmlns' || k.startsWith('xmlns:')) return;
      final (u, l) = resolve(k, attr: true);
      attrs['$u|$l'] = v;
    });
    final (uri, local) = resolve(qname, attr: false);
    final el = XmlElement(uri, local, attrs, []);
    if (s.codeUnitAt(i) == 0x2f) {
      if (!_at('/>')) _bad('malformed empty tag <$qname>');
      i += 2;
      return el;
    }
    i++; // >
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        el.children.add(text.toString());
        text.clear();
      }
    }

    while (true) {
      if (i >= s.length) _bad('<$qname> is never closed');
      if (_at('</')) {
        i += 2;
        final close = _name();
        if (close != qname) _bad('</$close> closes <$qname>');
        _ws();
        if (i >= s.length || s.codeUnitAt(i) != 0x3e) _bad('</$close>');
        i++;
        flush();
        return el;
      }
      if (_at('<!--')) {
        _skipPast('-->');
      } else if (_at('<![CDATA[')) {
        final end = s.indexOf(']]>', i);
        if (end < 0) _bad('unterminated CDATA');
        text.write(s.substring(i + 9, end));
        i = end + 3;
      } else if (_at('<?')) {
        _skipPast('?>');
      } else if (s.codeUnitAt(i) == 0x3c) {
        flush();
        el.children.add(_element(ns, depth + 1));
      } else {
        final next = s.indexOf('<', i);
        final end = next < 0 ? s.length : next;
        text.write(_decode(s.substring(i, end)));
        i = end;
      }
    }
  }

  String _decode(String raw) {
    if (!raw.contains('&')) return raw;
    final out = StringBuffer();
    var k = 0;
    while (k < raw.length) {
      final amp = raw.indexOf('&', k);
      if (amp < 0) {
        out.write(raw.substring(k));
        break;
      }
      out.write(raw.substring(k, amp));
      final semi = raw.indexOf(';', amp);
      if (semi < 0 || semi - amp > 12) _bad('stray "&"');
      final name = raw.substring(amp + 1, semi);
      out.write(switch (name) {
        'lt' => '<',
        'gt' => '>',
        'amp' => '&',
        'quot' => '"',
        'apos' => "'",
        _ when name.startsWith('#x') => _char(
          int.tryParse(name.substring(2), radix: 16),
        ),
        _ when name.startsWith('#') => _char(int.tryParse(name.substring(1))),
        _ => _bad('unknown entity "&$name;"'),
      });
      k = semi + 1;
    }
    return out.toString();
  }

  String _char(int? code) {
    if (code == null || code <= 0 || code > 0x10ffff) _bad('bad character');
    return String.fromCharCode(code);
  }
}
