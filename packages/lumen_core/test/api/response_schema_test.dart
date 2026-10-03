import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// Walks every JSON-schema node and calls [visit] on each object schema.
void _walk(Object? node, void Function(Map<String, Object?>) visit) {
  if (node is Map<String, Object?>) {
    if (node['type'] == 'object') visit(node);
    for (final v in node.values) {
      _walk(v, visit);
    }
  } else if (node is List) {
    for (final v in node) {
      _walk(v, visit);
    }
  }
}

void main() {
  group('AutoEditResponseSchema', () {
    final schema = AutoEditResponseSchema.build();

    test('every object has additionalProperties:false and a full required '
        'list', () {
      var objects = 0;
      _walk(schema, (obj) {
        objects++;
        expect(obj['additionalProperties'], isFalse, reason: '$obj');
        final props = (obj['properties']! as Map).keys.toSet();
        final required = (obj['required']! as List).toSet();
        expect(required, props, reason: 'required must list every property');
      });
      expect(objects, greaterThanOrEqualTo(7));
    });

    test('param enum equals ParamRegistry.aiEditableIds', () {
      final variants = (schema['properties']! as Map)['variants']! as Map;
      final variant = variants['items']! as Map;
      final adjustments =
          (variant['properties']! as Map)['adjustments']! as Map;
      final item = adjustments['items']! as Map;
      final param = (item['properties']! as Map)['param']! as Map;
      expect(param['enum'], ParamRegistry.aiEditableIds);
      expect(param['enum'], isNot(contains(P.sharpenRadius)));
    });

    test('atom enum lists the 13 style atoms', () {
      expect(kStyleAtomIds, hasLength(13));
      expect(jsonEncode(schema), contains('"cinematic_teal_orange"'));
    });

    test('reasoning fields come before variants (schema order)', () {
      final keys = (schema['properties']! as Map).keys.toList();
      expect(keys, ['scene', 'issues', 'intent', 'variants', 'done']);
    });

    test('no numeric min/max keywords (unsupported upstream)', () {
      final text = jsonEncode(schema);
      expect(text, isNot(contains('minimum')));
      expect(text, isNot(contains('maximum')));
    });

    test('is deterministic and JSON-encodable', () {
      expect(
        jsonEncode(AutoEditResponseSchema.build()),
        jsonEncode(AutoEditResponseSchema.build()),
      );
    });
  });
}
