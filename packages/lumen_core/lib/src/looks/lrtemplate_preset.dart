/// Legacy Lightroom develop presets (`.lrtemplate`): a Lua table literal,
/// `s = { title = "…", value = { settings = { Exposure2012 = 0.5, … } } }`.
///
/// The file is parsed as data only. Nothing is ever evaluated: only table
/// constructors, strings, numbers, booleans, nil and the localisation
/// wrappers `ZSTR "…"` / `LOC "…"` are accepted; any other expression
/// (a function call, an operator, a variable) rejects the file.
library;

import 'lightroom_mapping.dart';
import 'xmp_preset.dart' show PresetFormatException;

/// A Lua table: named fields and positional items.
class LuaTable {
  LuaTable(this.fields, this.items);
  final Map<String, Object?> fields;
  final List<Object?> items;
}

/// Parses `name = { … }` and returns the table. Throws
/// [PresetFormatException] for anything else.
LuaTable parseLuaAssignment(
  String text, {
  int maxChars = 4 * 1024 * 1024,
  int maxDepth = 32,
  int maxValues = 500000,
}) => _Lua(text, maxChars, maxDepth, maxValues).document();

/// Reads an `.lrtemplate` develop preset.
LightroomPresetData readLrTemplate(String text) {
  final s = parseLuaAssignment(text);
  final type = s.fields['type'];
  if (type is String && type != 'Develop') {
    throw PresetFormatException('A Lightroom "$type" template, not a preset.');
  }
  final value = s.fields['value'];
  final settings = value is LuaTable ? value.fields['settings'] : null;
  if (settings is! LuaTable) {
    throw const PresetFormatException(
      'Not a Lightroom develop preset (no settings).',
    );
  }
  final out = <String, Object?>{};
  settings.fields.forEach((k, v) => out[k] = _plain(v));
  final title = s.fields['title'];
  return LightroomPresetData(
    settings: out,
    name: title is String && title.trim().isNotEmpty ? title.trim() : null,
  );
}

/// Numbers, strings and booleans as they are; a list of plain values as a
/// list; any other table (masks, profiles) as an opaque [CrsStruct].
Object? _plain(Object? v) {
  if (v is! LuaTable) return v;
  final simple =
      v.fields.isEmpty && v.items.every((e) => e is num || e is String);
  if (simple) return List<Object?>.unmodifiable(v.items);
  final name = v.fields['name'] ?? v.fields['Name'];
  return CrsStruct(name is String ? name : null);
}

class _Lua {
  _Lua(this.s, this.maxChars, this.maxDepth, this.maxValues);

  final String s;
  final int maxChars;
  final int maxDepth;
  final int maxValues;
  int i = 0;
  int _values = 0;

  Never _bad(String why) =>
      throw PresetFormatException('Not a Lightroom preset: $why.');

  LuaTable document() {
    if (s.length > maxChars) {
      throw const PresetFormatException(
        'The file is too large to be a preset.',
      );
    }
    _skip();
    _ident();
    _skip();
    _expect('=');
    _skip();
    final v = _value(0);
    if (v is! LuaTable) _bad('the file does not assign a table');
    _skip();
    if (i < s.length) _bad('unexpected text after the table');
    return v;
  }

  bool _at(String t) => s.startsWith(t, i);

  void _expect(String t) {
    if (!_at(t)) _bad('expected "$t" at offset $i');
    i += t.length;
  }

  /// Whitespace and comments (`-- line`, `--[[ block ]]`, `--[==[ ]==]`).
  void _skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        i++;
      } else if (_at('--')) {
        i += 2;
        final long = _longOpen();
        if (long != null) {
          _longBody(long);
        } else {
          final nl = s.indexOf('\n', i);
          i = nl < 0 ? s.length : nl + 1;
        }
      } else {
        return;
      }
    }
  }

  /// At `[` `=`* `[`: returns the closing bracket and moves past the open.
  String? _longOpen() {
    if (!_at('[')) return null;
    var j = i + 1;
    while (j < s.length && s.codeUnitAt(j) == 0x3d) {
      j++;
    }
    if (j >= s.length || s.codeUnitAt(j) != 0x5b) return null;
    final eq = j - i - 1;
    i = j + 1;
    return ']${'=' * eq}]';
  }

  String _longBody(String close) {
    final end = s.indexOf(close, i);
    if (end < 0) _bad('unterminated long string or comment');
    var body = s.substring(i, end);
    if (body.startsWith('\r\n')) {
      body = body.substring(2);
    } else if (body.startsWith('\n')) {
      body = body.substring(1);
    }
    i = end + close.length;
    return body;
  }

  static bool _identStart(int c) =>
      (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a) || c == 0x5f;

  static bool _identChar(int c) => _identStart(c) || (c >= 0x30 && c <= 0x39);

  String _ident() {
    if (i >= s.length || !_identStart(s.codeUnitAt(i))) _bad('expected a name');
    final start = i;
    while (i < s.length && _identChar(s.codeUnitAt(i))) {
      i++;
    }
    return s.substring(start, i);
  }

  Object? _value(int depth) {
    if (++_values > maxValues) _bad('too many values');
    if (i >= s.length) _bad('unexpected end of file');
    final c = s.codeUnitAt(i);
    if (c == 0x7b) return _table(depth + 1);
    if (c == 0x22 || c == 0x27) return _string();
    if (_longOpen() case final close?) return _longBody(close);
    if (c == 0x2d || c == 0x2e || (c >= 0x30 && c <= 0x39)) return _number();
    if (_identStart(c)) {
      final id = _ident();
      switch (id) {
        case 'true':
          return true;
        case 'false':
          return false;
        case 'nil':
          return null;
        case 'ZSTR' || 'LOC':
          _skip();
          if (i < s.length && s.codeUnitAt(i) == 0x28) {
            i++;
            _skip();
            final v = _string();
            _skip();
            _expect(')');
            return _localized(v);
          }
          return _localized(_string());
      }
      _bad('"$id" is code, not data');
    }
    _bad('unexpected "${String.fromCharCode(c)}"');
  }

  /// `$$$/Key/Path=Default text` → `Default text`.
  static String _localized(String v) {
    if (!v.startsWith(r'$$$/')) return v;
    final eq = v.indexOf('=');
    return eq < 0 ? v.substring(v.lastIndexOf('/') + 1) : v.substring(eq + 1);
  }

  LuaTable _table(int depth) {
    if (depth > maxDepth) _bad('tables nested too deep');
    i++; // {
    final fields = <String, Object?>{};
    final items = <Object?>[];
    while (true) {
      _skip();
      if (i >= s.length) _bad('a table is never closed');
      if (s.codeUnitAt(i) == 0x7d) {
        i++;
        return LuaTable(fields, items);
      }
      if (s.codeUnitAt(i) == 0x5b && !_at('[[') && !_at('[=')) {
        i++;
        _skip();
        final key = _value(depth);
        _skip();
        _expect(']');
        _skip();
        _expect('=');
        _skip();
        fields[key.toString()] = _value(depth);
      } else if (_identStart(s.codeUnitAt(i)) && _isFieldName()) {
        final key = _ident();
        _skip();
        _expect('=');
        _skip();
        fields[key] = _value(depth);
      } else {
        items.add(_value(depth));
      }
      _skip();
      if (i < s.length &&
          (s.codeUnitAt(i) == 0x2c || s.codeUnitAt(i) == 0x3b)) {
        i++;
      } else if (i < s.length && s.codeUnitAt(i) != 0x7d) {
        _bad('expected "," or "}" at offset $i');
      }
    }
  }

  /// True when the identifier at [i] is followed by `=` (not `==`).
  bool _isFieldName() {
    var j = i;
    while (j < s.length && _identChar(s.codeUnitAt(j))) {
      j++;
    }
    while (j < s.length && ' \t\r\n'.contains(s[j])) {
      j++;
    }
    return j < s.length &&
        s[j] == '=' &&
        (j + 1 >= s.length || s[j + 1] != '=');
  }

  String _string() {
    if (i >= s.length) _bad('expected a string');
    final q = s.codeUnitAt(i);
    if (q != 0x22 && q != 0x27) _bad('expected a string');
    i++;
    final out = StringBuffer();
    while (true) {
      if (i >= s.length) _bad('unterminated string');
      final c = s.codeUnitAt(i);
      if (c == q) {
        i++;
        return out.toString();
      }
      if (c == 0x0a) _bad('line break inside a string');
      if (c != 0x5c) {
        out.writeCharCode(c);
        i++;
        continue;
      }
      i++;
      if (i >= s.length) _bad('unterminated string');
      final e = s[i];
      i++;
      switch (e) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case '\n':
          out.write('\n');
        case '\\' || '"' || "'":
          out.write(e);
        default:
          if (RegExp(r'[0-9]').hasMatch(e)) {
            var digits = e;
            while (digits.length < 3 &&
                i < s.length &&
                RegExp(r'[0-9]').hasMatch(s[i])) {
              digits += s[i++];
            }
            out.writeCharCode(int.parse(digits).clamp(0, 255));
          } else {
            out.write(e);
          }
      }
    }
  }

  num _number() {
    final m = RegExp(
      r'-?\s*(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?)',
    ).matchAsPrefix(s, i);
    if (m == null) _bad('expected a number at offset $i');
    i = m.end;
    final text = m.group(0)!.replaceAll(RegExp(r'\s'), '');
    final neg = text.startsWith('-');
    final body = neg ? text.substring(1) : text;
    final v = body.toLowerCase().startsWith('0x')
        ? int.parse(body.substring(2), radix: 16)
        : num.parse(body);
    return neg ? -v : v;
  }
}
