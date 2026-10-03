/// Builds the raw `POST /v1/messages` request (PLAN §1.9 "Upstream call").
///
/// Never sends `temperature`/`top_p`, `thinking` (Opus 5.5 always thinks;
/// effort is the only knob), `tool_choice` or an assistant prefill.
library;

const String kAnthropicVersion = '2023-06-01';
const String kFallbackBeta = 'server-side-fallback-2026-07-01';

/// Models that support Anthropic's server-side refusal fallback.
const Set<String> kFallbackModels = {
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-sonnet-5-5',
  'claude-fable-5-1',
};

bool supportsFallback(String model) => kFallbackModels.contains(model);

class MessagesRequest {
  const MessagesRequest({
    required this.model,
    required this.effort,
    required this.maxTokens,
    required this.systemPrompt,
    required this.schema,
    required this.imageMime,
    required this.imageBase64,
    required this.userText,
  });

  final String model;
  final String effort;
  final int maxTokens;

  /// Byte-stable system prompt (cached with `cache_control`).
  final String systemPrompt;

  /// JSON schema for `output_config.format`.
  final Map<String, Object?> schema;
  final String imageMime;
  final String imageBase64;

  /// Stats, EXIF, baseline, style and instruction. Goes after the image.
  final String userText;

  Map<String, String> headers(String apiKey) => {
    'x-api-key': apiKey,
    'anthropic-version': kAnthropicVersion,
    'content-type': 'application/json',
    if (supportsFallback(model)) 'anthropic-beta': kFallbackBeta,
  };

  Map<String, Object?> toJson() => {
    'model': model,
    'max_tokens': maxTokens,
    'system': [
      {
        'type': 'text',
        'text': systemPrompt,
        'cache_control': {'type': 'ephemeral'},
      },
    ],
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': imageMime,
              'data': imageBase64,
            },
          },
          {'type': 'text', 'text': userText},
        ],
      },
    ],
    'output_config': {
      'format': {'type': 'json_schema', 'schema': schema},
      'effort': effort,
    },
    if (supportsFallback(model)) 'fallbacks': 'default',
  };
}
