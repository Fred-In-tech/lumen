import 'dart:math' as math;

import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'atoms.dart';
import 'auto_edit_provider.dart';
import 'lexicon_vocab.dart';
import 'reasons.dart';

/// One clause of an instruction ("lift the shadows a bit").
class InstructionClause {
  const InstructionClause(this.text, this.ops, {this.atoms = const []});

  final String text;
  final List<EditOp> ops;

  /// Style atoms this clause referenced.
  final List<StyleAtom> atoms;

  bool get recognized => ops.isNotEmpty;
}

/// What applying an instruction did.
class InstructionOutcome {
  const InstructionOutcome(this.settings, this.changes, this.notes);

  final DevelopSettings settings;
  final List<ParamChange> changes;

  /// Explanations for parts that had no effect.
  final List<String> notes;
}

/// A parsed instruction: clauses with ops, plus suggestion chips.
class InstructionResult {
  const InstructionResult(this.instruction, this.clauses, this.suggestions);

  /// Nothing was understood; [suggestions] are shown as chips.
  factory InstructionResult.unrecognized(
    String instruction,
    List<String> suggestions,
  ) => InstructionResult(instruction, const [], suggestions);

  final String instruction;
  final List<InstructionClause> clauses;
  final List<String> suggestions;

  bool get isRecognized => clauses.any((c) => c.recognized);

  List<String> get unrecognizedClauses => [
    for (final c in clauses)
      if (!c.recognized) c.text,
  ];

  /// All ops, resolving conflicts in favor of the later clause.
  List<EditOp> get ops {
    final claimed = <String>{};
    final out = <EditOp>[];
    for (final clause in clauses.reversed) {
      out.insertAll(0, clause.ops.where((op) => !claimed.contains(_key(op))));
      claimed.addAll(clause.ops.map(_key));
    }
    return out;
  }

  /// Applies the instruction to [current]. "Less X" never goes past
  /// [baseline] (the pre-instruction / pre-AI state, default [current]).
  InstructionOutcome apply(
    DevelopSettings current, {
    DevelopSettings? baseline,
    Set<ParamId> locked = const {},
  }) {
    final r = applyOps(
      current,
      ops,
      baseline: baseline ?? current,
      locked: locked,
      caps: InstructionCaps.standard,
    );
    final changes = Reasons.diff(
      current,
      r.settings,
      (p, from, to) => Reasons.instruction(instruction, p, from, to),
    );
    return InstructionOutcome(r.settings, changes, r.notes.toSet().toList());
  }
}

String _key(EditOp op) => switch (op) {
  DeltaOp(:final param) || SetOp(:final param) || LessOp(:final param) => param,
  CurveOp() => '#curve',
  TreatmentOp() => '#treatment',
};

/// Offline describe-an-edit parser (research 01 §7, PLAN.md §1.8).
abstract final class Lexicon {
  static final _tokenRe = RegExp(r'[+-]?\d+(?:\.\d+)?|[a-z]+|[,;.]');
  static final _numberRe = RegExp(r'^[+-]?\d');

  static InstructionResult parse(String instruction) {
    final tokens = tokenize(instruction);
    final clauses = <InstructionClause>[];
    var current = <String>[];
    void flush() {
      if (current.isNotEmpty) clauses.add(_parseClause(current));
      current = <String>[];
    }

    for (final t in tokens) {
      if (kClauseBreaks.contains(t)) {
        flush();
      } else {
        current.add(t);
      }
    }
    flush();
    final suggestions = _suggest(tokens);
    if (!clauses.any((c) => c.recognized)) {
      return InstructionResult.unrecognized(instruction, suggestions);
    }
    return InstructionResult(
      instruction,
      List.unmodifiable(clauses),
      suggestions,
    );
  }

  /// Lower-cases, protects multi-word phrases and splits into tokens.
  static List<String> tokenize(String instruction) {
    var t = ' ${instruction.toLowerCase()} '
        .replaceAll('−', '-')
        .replaceAll('–', '-');
    for (final (from, to) in kProtectedPhrases) {
      t = t.replaceAll(from, to);
    }
    return [for (final m in _tokenRe.allMatches(t)) m.group(0)!];
  }

  static InstructionClause _parseClause(List<String> tokens) {
    final text = tokens.join(' ');
    final sliderToken = tokens.firstWhere(
      kSliderWords.containsKey,
      orElse: () => '',
    );
    final slider = kSliderWords[sliderToken];
    final number = tokens.firstWhere(_numberRe.hasMatch, orElse: () => '');
    final down = tokens.any(kDownWords.contains);
    if (slider != null && number.isNotEmpty) {
      final v = double.parse(number);
      final EditOp op;
      if (number.startsWith('+') || number.startsWith('-')) {
        op = DeltaOp(slider.param, v, explicit: true);
      } else if (tokens.contains('by')) {
        op = DeltaOp(slider.param, down ? -v : v, explicit: true);
      } else {
        op = SetOp(slider.param, v, explicit: true);
      }
      return InstructionClause(text, [op]);
    }

    final mult = intensityOf(tokens);
    final less = tokens.any(kLessWords.contains);
    final fraction = (0.5 * mult).clamp(0.25, 1.0).toDouble();
    if (slider != null) {
      return InstructionClause(text, [
        _sliderOp(slider, tokens, mult, fraction, less: less, down: down),
      ]);
    }

    final atoms = _atomsIn(tokens);
    if (atoms.isNotEmpty) {
      return InstructionClause(text, [
        for (final a in atoms) ...(less ? a.lessOps(fraction) : a.ops(mult)),
      ], atoms: atoms);
    }

    for (final t in tokens) {
      final sign = kBrightnessWords[t];
      if (sign != null) {
        return InstructionClause(text, [
          DeltaOp(P.exposure, sign * kSliderWords['exposure']!.unit * mult),
        ]);
      }
    }
    return InstructionClause(text, const []);
  }

  static EditOp _sliderOp(
    SliderWord w,
    List<String> tokens,
    double mult,
    double fraction, {
    required bool less,
    required bool down,
  }) {
    if (!w.lessMeansDown && (less || tokens.contains('remove'))) {
      final f = tokens.contains('remove') ? 1.0 : fraction;
      return LessOp(w.param, f, w.moreSign, named: true);
    }
    final dir = (down || less) ? -1 : 1;
    return DeltaOp(w.param, dir * w.moreSign * w.unit * mult, named: true);
  }

  /// Intensity multiplier of research 01 §7.2 (longest phrase wins).
  static double intensityOf(List<String> tokens) {
    var bestLen = 0;
    var best = 1.0;
    for (final (phrase, value) in kIntensityPhrases) {
      if (phrase.length <= bestLen) continue;
      for (var i = 0; i + phrase.length <= tokens.length; i++) {
        var ok = true;
        for (var k = 0; k < phrase.length && ok; k++) {
          ok = tokens[i + k] == phrase[k];
        }
        if (ok) {
          bestLen = phrase.length;
          best = value;
          break;
        }
      }
    }
    return best;
  }

  static List<StyleAtom> _atomsIn(List<String> tokens) {
    final found = <StyleAtom>[
      for (final (atom, words) in kAtomWords)
        if (tokens.any(words.contains)) atom,
    ];
    for (final e in kAtomSubsumes.entries) {
      if (found.contains(e.key)) found.remove(e.value);
    }
    return found;
  }

  static List<String> _suggest(List<String> tokens) {
    final scored = <(int, int, String)>[];
    for (final t in tokens) {
      if (t.length < 4 || kKnownWords.contains(t) || _isStructural(t)) {
        continue;
      }
      for (var i = 0; i < kKnownWords.length; i++) {
        final w = kKnownWords[i];
        final d = _editDistance(t, w);
        if (d <= 2 && d < t.length / 2) scored.add((d, i, w));
      }
    }
    scored.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    final out = <String>[for (final s in scored) s.$3];
    for (final d in kDefaultSuggestions) {
      if (out.length >= 5) break;
      out.add(d);
    }
    return List.unmodifiable(out.toSet().take(5));
  }

  static bool _isStructural(String t) =>
      kUpWords.contains(t) ||
      kDownWords.contains(t) ||
      kLessWords.contains(t) ||
      kIntensityPhrases.any((p) => p.$1.contains(t));

  static int _editDistance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = math.min(
          math.min(cur[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
