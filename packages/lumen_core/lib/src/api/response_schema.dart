/// JSON schema for what Claude returns (`AutoEditResponse`), generated from
/// [ParamRegistry] so the app, the gateway and the prompt can never disagree
/// about parameter ids.
///
/// Structured outputs require `additionalProperties: false` on every object
/// and do not enforce numeric `minimum`/`maximum`, so ranges are clamped
/// after parsing (see `auto_edit_response.dart`).
library;

import '../model/param_registry.dart';

/// The 13 style atoms (research 01 §7.3), in a stable order.
const List<String> kStyleAtomIds = [
  'warm',
  'cool',
  'bright_airy',
  'moody',
  'punchy',
  'soft_matte',
  'cinematic_teal_orange',
  'film_faded',
  'golden_hour',
  'sky_pop',
  'vibrant',
  'muted',
  'bw_classic',
];

const List<String> kTimeOfDayValues = [
  'day',
  'golden_hour',
  'blue_hour',
  'night',
  'indoor',
  'unknown',
];
const List<String> kKeyIntentValues = ['low_key', 'normal', 'high_key'];
const List<String> kSeverityValues = ['low', 'medium', 'high'];
const List<String> kContrastLevelValues = ['low', 'medium', 'high'];
const List<String> kColorLevelValues = ['muted', 'natural', 'vivid'];

abstract final class AutoEditResponseSchema {
  /// Builds a fresh schema map. Key order is the output order: reasoning
  /// fields (`scene`, `issues`, `intent`) come before `variants` so the model
  /// analyses before it writes numbers.
  static Map<String, Object?> build() => _object({
    'scene': _object({
      'subject': _string,
      'lighting': _string,
      'timeOfDay': _enum(kTimeOfDayValues),
      'keyIntent': _enum(kKeyIntentValues),
    }),
    'issues': _array(
      _object({'issue': _string, 'severity': _enum(kSeverityValues)}),
    ),
    'intent': _string,
    'variants': _array(
      _object({
        'label': _string,
        'confidence': _number,
        'targets': _object({
          'midLStar': _number,
          'wbStrength': _number,
          'contrastLevel': _enum(kContrastLevelValues),
          'colorLevel': _enum(kColorLevelValues),
        }),
        'presetAtoms': _array(
          _object({'atom': _enum(kStyleAtomIds), 'amount': _number}),
        ),
        'adjustments': _array(
          _object({
            'param': _enum(ParamRegistry.aiEditableIds),
            'value': _number,
            'reason': _string,
          }),
        ),
      }),
    ),
    'done': {'type': 'boolean'},
  });

  static const Map<String, Object?> _string = {'type': 'string'};
  static const Map<String, Object?> _number = {'type': 'number'};

  static Map<String, Object?> _enum(List<String> values) => {
    'type': 'string',
    'enum': List<String>.of(values),
  };

  static Map<String, Object?> _array(Map<String, Object?> items) => {
    'type': 'array',
    'items': items,
  };

  static Map<String, Object?> _object(Map<String, Object?> properties) => {
    'type': 'object',
    'additionalProperties': false,
    'required': properties.keys.toList(),
    'properties': properties,
  };
}
