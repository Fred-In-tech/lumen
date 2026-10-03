/// The variable part of the prompt (after the image). Stable fields first,
/// style and instruction last, so the shared prefix stays cache-friendly.
library;

import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';

String _json(Object? value) => jsonEncode(value);

String buildUserText(AutoEditRequest request, {String? instruction}) {
  final refine = instruction != null;
  final buffer = StringBuffer()
    ..writeln('Image 1: photo to edit.')
    ..writeln('<stats>${_json(request.stats)}</stats>')
    ..writeln('<exif>${_json(request.exif?.toJson() ?? const {})}</exif>')
    ..writeln('<baseline>${_json(request.baseline)}</baseline>')
    ..writeln('<current>${_json(request.current)}</current>')
    ..writeln('<locked>${_json(request.locked)}</locked>')
    ..writeln('Mode: ${refine ? 'refine' : 'initial'}')
    ..writeln('Variants: ${refine ? 1 : request.variants}')
    ..writeln('Style: ${request.style.label}');
  if (refine) {
    // Angle brackets are stripped so the text cannot close the tag.
    final safe = instruction.replaceAll(RegExp('[<>]'), ' ');
    buffer.writeln('<instruction>$safe</instruction>');
  }
  return buffer.toString();
}
